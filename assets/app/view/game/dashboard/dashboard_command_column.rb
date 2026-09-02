# frozen_string_literal: true
# backtick_javascript: true

# rubocop:disable Layout/LineLength

require 'view/game/actionable'
require 'view/game/abilities'
require 'view/game/buy_companies'
require 'view/game/dashboard/results_overlay'
require 'view/game/dashboard/dashboard_stock'
require 'view/game/dashboard/dashboard_card_animation'
require 'view/game/history_and_undo'

module View
  module Game
    class DashboardCommandColumn < Snabberb::Component
      include Actionable
      include Lib::Settings

      needs :game, store: true
      needs :game_data, store: true, default: nil
      needs :routes, store: true, default: []
      needs :last_routed_action_id, store: true, default: nil
      needs :last_entity, store: true, default: nil
      needs :cmd_router_running, store: true, default: false

def current_entity
  @game.round.active_step&.current_entity ||
    (@game.round.respond_to?(:current_entity) ? @game.round.current_entity : nil) ||
    @game.current_entity
rescue NotImplementedError, StandardError
  nil
end

      def active_routes
        @routes.select { |r| r.chains.any? }
      end

     def render_action_row(label, children)
        items = (children.is_a?(Array) ? children : [children]).compact
        return nil if items.empty?

        h(:div, {
          style: {
            display: 'flex',
            flexDirection: 'row',
            alignItems: 'center',
            justifyContent: 'flex-start',
            gap: '0.5rem',
            width: '100%',
            maxWidth: '100%',
            margin: '0 auto',
          },
        }, [
          h(:span, { style: { fontSize: '0.95rem', fontWeight: 'bold', color: '#333', minWidth: '6.5rem', textAlign: 'left', flexShrink: '0' } }, label),
          h(:div, { style: { display: 'flex', flexDirection: 'row', flexWrap: 'nowrap', alignItems: 'center', gap: '0.35rem' } }, items),
        ])
      end

      def render_company_tooltip(title, subtitle, desc, val, rev, owner)
        h(:div, {
          attrs: { class: 'cmd-company-tooltip' },
          style: {
            display: 'none',
            position: 'fixed',
            top: '8rem',
            left: '25%',
            transform: 'translateX(-50%)',
            width: '300px',
            backgroundColor: '#ffffff',
            border: '2px solid #333333',
            borderRadius: '6px',
            padding: '8px',
            boxShadow: '0 8px 24px rgba(0,0,0,0.35)',
            zIndex: '99999',
            pointerEvents: 'none',
            color: '#000000',
            textAlign: 'left',
            boxSizing: 'border-box',
          },
        }, [
          h(:div, {
            style: {
              backgroundColor: '#ffff00',
              border: '1px solid #000000',
              fontWeight: 'bold',
              fontSize: '0.8rem',
              textAlign: 'center',
              padding: '2px 4px',
              marginBottom: '4px',
              textTransform: 'uppercase',
              borderRadius: '3px',
            },
          }, title),
          h(:div, { style: { fontWeight: 'bold', fontSize: '0.9rem', textAlign: 'center', marginBottom: '4px' } }, subtitle),
          h(:div, { style: { fontSize: '0.78rem', lineHeight: '1.25', marginBottom: '6px', color: '#222222' } }, desc),
          h(:div, { style: { display: 'flex', justifyContent: 'space-between', fontSize: '0.78rem', fontWeight: 'bold', borderTop: '1px solid #ddd', paddingTop: '4px', marginBottom: '2px' } }, [
            h(:span, "Value: #{val}"),
            h(:span, "Revenue: #{rev}"),
          ]),
          h(:div, { style: { fontSize: '0.78rem', fontWeight: 'bold', textAlign: 'center', color: '#555555' } }, "Owner: #{owner}"),
        ])
      end


def render_zone3_abilities(entity)
        return nil unless entity

        active_ability_companies = (@game.companies || []).select do |c|
          next false if c.respond_to?(:closed?) && c.closed?
          
          is_owner = c.owner == entity || (entity.respond_to?(:owner) && c.owner && c.owner == entity.owner)
          next false unless is_owner

          c_actions = begin
                        @game.round.actions_for(c)
                      rescue StandardError
                        []
                      end || []
          
          next false if c_actions.empty?

          if @game.respond_to?(:entity_can_use_company?)
            next false unless @game.entity_can_use_company?(entity, c)
          end

          true
        end

        return nil if active_ability_companies.empty?

        ability_boxes = active_ability_companies.map do |c|
          owner_name = c.owner&.name || 'Bank'
          card_text = (c.sym || c.name).to_s

          desc_text = if c.respond_to?(:desc) && c.desc && !c.desc.empty?
                        c.desc
                      elsif c.respond_to?(:abilities) && c.abilities&.any?
                        c.abilities.map { |a| a.respond_to?(:description) ? a.description : nil }.compact.join(' ')
                      else
                        'No special abilities.'
                      end

          value_str = @game.format_currency(c.value || 0)
          revenue_str = @game.format_currency(c.revenue || 0)

          tooltip_card = render_company_tooltip('Private Company', c.name, desc_text, value_str, revenue_str, owner_name)

          click_handler = lambda {
            c_actions = begin
                          @game.round.actions_for(c)
                        rescue StandardError
                          []
                        end || []

            # 1. Direct bypass for Exchange abilities (e.g. Mohawk & Hudson)
            if c_actions.include?('buy_shares') && (ability = @game.abilities(c, :exchange))
              step = @game.round.active_step(c)
              valid_shares = []
              if step.respond_to?(:can_gain?)
                @game.exchange_corporations(ability).each do |corp|
                  ipo_share = corp.shares.find { |s| !s.president }
                  valid_shares << ipo_share if ipo_share && ability.from.include?(:ipo) && step.can_gain?(c.owner, ipo_share, exchange: true)

                  pool_share = @game.share_pool.shares_by_corporation[corp]&.first
                  valid_shares << pool_share if pool_share && ability.from.include?(:market) && step.can_gain?(c.owner, pool_share, exchange: true)

                  reserved = corp.reserved_shares&.first
                  valid_shares << reserved if reserved && ability.from.include?(:reserved) && step.can_gain?(c.owner, reserved, exchange: true)
                end
              end
              if valid_shares.any?
                process_action(Engine::Action::BuyShares.new(c, shares: valid_shares.first))
                next
              end
            end

            # 2. Direct bypass for Sell/Close/Purchase Train abilities
            if c_actions.include?('sell_company')
              process_action(Engine::Action::SellCompany.new(entity, company: c, price: c.value))
              next
            end

            if c_actions.include?('purchase_train')
              process_action(Engine::Action::PurchaseTrain.new(c))
              next
            end

            if c_actions.include?('manual_close_company')
              process_action(Engine::Action::ManualCloseCompany.new(c))
              next
            end

            # 3. Standard fallback for generic abilities
            store(:selected_company, c)
            active_a = (c.respond_to?(:all_abilities) ? c.all_abilities : []).dup.concat(c.abilities || []).find do |a|
              !((a.respond_to?(:passive?) && a.passive?) || (a.respond_to?(:passive) && a.passive) || (a.respond_to?(:closed?) && a.closed?) || (a.respond_to?(:used?) && a.used?))
            end

            if active_a && !%i[tile_lay token teleport hex_bonus choose_ability assign_corporation].include?(active_a.type)
              begin
                process_action(Engine::Action::UseAbility.new(c, ability: active_a, company: c))
              rescue StandardError
                begin
                  process_action(Engine::Action::UseAbility.new(entity, ability: active_a, company: c))
                rescue StandardError => e
                  `console.warn('UseAbility failed: ' + e)`
                end
              end
            end
          }

          card_props = {
            attrs: { class: 'game-card clickable action-buy' },
            style: {
              border: '2px solid #28a745',
              minWidth: '3.5rem',
              height: '1.45rem',
              padding: '0 4px',
              margin: '0',
              boxSizing: 'border-box',
              cursor: 'pointer',
            },
            on: { click: click_handler },
          }

          h(:div, {
            attrs: { class: 'cmd-company-wrapper' },
            style: { display: 'inline-block', position: 'relative' },
          }, [
            tooltip_card,
            h(:div, card_props, card_text),
          ])
        end

        h(:div, {
          style: {
            width: '100%',
            display: 'flex',
            flexDirection: 'row',
            alignItems: 'center',
            justifyContent: 'space-between',
            gap: '0.4rem',
            height: '1.8rem',
          },
        }, [
          h(:span, { style: { fontSize: '0.95rem', fontWeight: 'bold', color: '#333', flexShrink: '0' } }, 'Abilities:'),
          h(:div, { style: { display: 'flex', flexDirection: 'row', alignItems: 'center', gap: '0.3rem', flexWrap: 'wrap' } }, ability_boxes),
        ])
      end









      def render
        step = @game.round.active_step
        entity = current_entity

        if @last_entity != entity
          store(:last_entity, entity, skip: true)
          @routes = []
          store(:routes, @routes, skip: true)
        end

        last_action = @game.respond_to?(:raw_actions) && @game.raw_actions ? @game.raw_actions.last : nil
        last_action_id = if last_action.is_a?(Hash)
                           last_action['id'] || last_action[:id] || 0
                         elsif last_action.respond_to?(:id)
                           last_action.id
                         elsif @game_data && @game_data['actions']
                           @game_data['actions'].last&.fetch('id', 0) || 0
                         else
                           0
                         end

        actions = if entity && @game.round.respond_to?(:actions_for)
                    begin
                      @game.round.actions_for(entity)
                    rescue NotImplementedError, StandardError
                      []
                    end
                  else
                    []
                  end

        phase = :waiting
        if actions.include?('lay_tile')
          phase = :build_track
        elsif actions.include?('place_token')
          phase = :place_token
        elsif actions.include?('run_routes')
          phase = :run_routes
        elsif actions.include?('dividend') || actions.include?('payout') || actions.include?('withhold') || actions.include?('half') || actions.include?('split')
          phase = :dividend
        elsif actions.include?('buy_train')
          phase = :buy_train
        elsif actions.include?('discard_train')
          phase = :discard_train
        elsif actions.include?('issue_shares')
          phase = :issue_shares
        end

        `console.log('DCC Turn State:', {
          entity: #{entity&.id || 'nil'},
          entity_class: #{entity&.class&.name || 'nil'},
          step: #{step&.class&.name || 'nil'},
          phase: #{phase.to_s},
          actions: #{actions.to_n}
        })`

        player_name = entity&.owner&.name || ''

        if entity.respond_to?(:color)
          bg_color = entity.color || '#4169e1'
          text_color = entity.text_color || 'white'
        else
          bg_color = '#333333'
          text_color = 'white'
          player_name = entity&.name || ''
        end

        base_revenue = 0
        if active_routes.any? && !@cmd_router_running
          active_routes.each do |r|
            base_revenue += r.revenue if r.chains.any?
          rescue Engine::GameError
          rescue StandardError
          end
        end
        if phase == :dividend && base_revenue.zero? && entity.respond_to?(:operating_history)
          operating = entity.operating_history || {}
          base_revenue = (operating[operating.keys.max]&.revenue || 0).to_i
        end

        storage_key = "rev_override_#{entity&.id}"
        last_base_key = "last_base_rev_#{entity&.id}"

        if Lib::Storage[last_base_key] != base_revenue
          Lib::Storage[storage_key] = base_revenue
          Lib::Storage[last_base_key] = base_revenue
        end

        current_revenue = Lib::Storage[storage_key].to_i
        formatted_revenue = @game.format_revenue_currency(current_revenue)

        if @game.finished
          return h(:div, { style: { display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '100%' } }, [
            h(:div, { style: { fontSize: '2rem', fontWeight: 'bold', marginBottom: '1rem' } }, 'End of Game'),
            h(:button, {
              style: { padding: '1rem 2rem', fontSize: '1.2rem', backgroundColor: '#28a745', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold' },
              on: { click: -> { Lib::Storage['show_results_overlay'] = true; update } },
            }, 'Show Results'),
            (Lib::Storage['show_results_overlay'] ? h(View::Game::Dashboard::ResultsOverlay, game: @game) : nil),
          ].compact)
        end

        # --- ZONE 1: IDENTITY & TURN STATE ---
        if @game.round.stock?
          zone_1 = h(:div, { style: { flex: '0 0 20%', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '0.5rem', borderRight: '1px solid #ccc', boxSizing: 'border-box' } }, [
            h(:div, { style: { fontSize: '1.8rem', fontWeight: 'bold', color: '#000000', textAlign: 'center', wordBreak: 'break-word' } }, player_name),
            h(:div, { style: { fontSize: '1.1rem', fontWeight: 'bold', color: '#666', marginTop: '0.25rem' } }, 'STOCK ROUND'),
          ])
        else
          phase_labels = {
            waiting: 'WAITING',
            build_track: 'LAY TILE',
            place_token: 'PLACE TOKEN',
            run_routes: 'RUN ROUTES',
            dividend: 'DIVIDEND',
            buy_train: 'BUY TRAIN',
            discard_train: 'DISCARD TRAIN',
            issue_shares: 'ISSUE SHARES',
          }
          phase_text = phase_labels[phase] || 'ACTION REQUIRED'

          logo_src = begin
            setting_for(:simple_logos, @game) ? entity&.simple_logo : entity&.logo
          rescue StandardError
            nil
          end

          logo_element = if logo_src
                           h(:img, { attrs: { src: logo_src }, style: { width: '75px', height: '75px', objectFit: 'contain', marginRight: '0.75rem', flexShrink: '0' } })
                         else
                           h(:div, { style: { width: '75px', height: '75px', fontSize: '1.5rem', fontWeight: 'bold', display: 'flex', alignItems: 'center', justifyContent: 'center', backgroundColor: bg_color, color: text_color, borderRadius: '6px', marginRight: '0.75rem', flexShrink: '0' } }, entity&.id || 'N/A')
                         end

          zone_1 = h(:div, { style: { flex: '0 0 22%', display: 'flex', flexDirection: 'row', alignItems: 'center', padding: '0.4rem', borderRight: '1px solid #ccc', boxSizing: 'border-box', overflow: 'hidden' } }, [
            logo_element,
            h(:div, { style: { display: 'flex', flexDirection: 'column', justifyContent: 'center', overflow: 'hidden' } }, [
              h(:div, { style: { fontSize: '1.5rem', fontWeight: 'bold', color: '#000000', lineHeight: '1.2', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' } }, player_name),
              h(:div, { style: { fontSize: '1.5rem', fontWeight: 'bold', color: '#000000', lineHeight: '1.2', textTransform: 'uppercase', marginTop: '0.2rem' } }, phase_text),
            ]),
          ])
        end

        # --- ZONE 2: EXPANDED DYNAMIC ACTION CANVAS ---
        zone_2_content = []

        if phase == :run_routes
          if @cmd_router_running
            zone_2_content << h(:div, { style: { padding: '0.2rem', textAlign: 'center', color: '#666', fontStyle: 'italic', fontSize: '0.9rem' } }, '🔄 Computing optimal network tracks...')
          else
            zone_2_content << render_action_row('Revenue:', [
              h(:button, { style: { width: '1.8rem', height: '1.8rem', fontSize: '1.1rem', fontWeight: 'bold', cursor: 'pointer', backgroundColor: '#e0e0e0', border: '1px solid #999', borderRadius: '4px', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', padding: '0', lineHeight: '1' }, on: { click: -> { Lib::Storage[storage_key] = [current_revenue - 10, 0].max; update } } }, '-'),
              h(:div, { style: { fontSize: '1.2rem', fontWeight: 'bold', color: '#28a745', fontFamily: '"Courier New", Courier, monospace', minWidth: '4.5rem', textAlign: 'center', height: '1.8rem', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', lineHeight: '1' } }, formatted_revenue),
              h(:button, { style: { width: '1.8rem', height: '1.8rem', fontSize: '1.1rem', fontWeight: 'bold', cursor: 'pointer', backgroundColor: '#e0e0e0', border: '1px solid #999', borderRadius: '4px', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', padding: '0', lineHeight: '1' }, on: { click: -> { Lib::Storage[storage_key] = current_revenue + 10; update } } }, '+'),
            ])
          end
        elsif phase == :dividend
          raw_options = if step.respond_to?(:dividend_options)
                          step.dividend_options(entity)
                        elsif step.respond_to?(:dividend_types)
                          step.dividend_types
                        else
                          []
                        end
          options = (raw_options.is_a?(Hash) ? raw_options.keys : Array(raw_options)).map(&:to_s)
          half_kind = options.include?('split') ? 'split' : 'half'

          zone_2_content << h(:div, { style: { display: 'flex', flexDirection: 'row', justifyContent: 'center', gap: '0.5rem', width: '100%', maxWidth: '520px', margin: '0 auto' } }, [
            (h(:button, { style: { flex: '1', padding: '0.45rem 0.6rem', fontSize: '1.1rem', fontWeight: 'bold', backgroundColor: '#28a745', color: '#fff', border: 'none', borderRadius: '4px', cursor: 'pointer' }, on: { click: -> { process_action(Engine::Action::Dividend.new(entity, kind: 'payout', extra_revenue: current_revenue - base_revenue)) } } }, 'Pay Out Full') if actions.include?('payout') || options.include?('payout') || actions.include?('dividend')),
            (h(:button, { style: { flex: '1', padding: '0.45rem 0.6rem', fontSize: '1.1rem', fontWeight: 'bold', backgroundColor: '#007bff', color: '#fff', border: 'none', borderRadius: '4px', cursor: 'pointer' }, on: { click: -> { process_action(Engine::Action::Dividend.new(entity, kind: 'withhold', extra_revenue: current_revenue - base_revenue)) } } }, 'Hold Revenue') if actions.include?('withhold') || options.include?('withhold') || actions.include?('dividend')),
            (h(:button, { style: { flex: '1', padding: '0.45rem 0.6rem', fontSize: '1.1rem', fontWeight: 'bold', backgroundColor: '#007bff', color: '#fff', border: 'none', borderRadius: '4px', cursor: 'pointer' }, on: { click: -> { process_action(Engine::Action::Dividend.new(entity, kind: half_kind, extra_revenue: current_revenue - base_revenue)) } } }, 'Split / Half') if actions.include?('half') || actions.include?('split') || options.include?('half') || options.include?('split')),
          ].compact)
        end

        zone_2_content << render_ground_truth_actions(actions, step)

        zone_2 = h(:div, { style: { flex: '1 1 56%', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: '0.55rem', padding: '0.4rem', borderRight: '1px solid #ccc', boxSizing: 'border-box', overflowY: 'auto' } }, zone_2_content.compact)

        # --- ZONE 3: ACTIVE POWERS & ADVANCE ---
        advance_text = 'Pass'
        advance_color = '#e0e0e0'
        advance_text_color = '#a0a0a0'
        advance_disabled = true
        advance_action = -> {}

        if actions.include?('pass')
          advance_disabled = false
          advance_color = '#fd7e14'
          advance_text_color = '#fff'
          advance_action = -> { process_action(Engine::Action::Pass.new(entity)) }

          case phase
          when :build_track then advance_text = 'Skip Build'
          when :place_token then advance_text = 'Skip Token'
          when :buy_train then advance_text = 'Done Buying'
          when :issue_shares then advance_text = 'Skip Issue'
          end
        elsif phase == :run_routes && actions.include?('run_routes') && !@cmd_router_running
          advance_disabled = false
          advance_color = '#fd7e14'
          advance_text_color = '#fff'
          advance_text = "Submit #{formatted_revenue}"
          advance_action = lambda {
            routes_to_submit = active_routes
            process_action(Engine::Action::RunRoutes.new(
              entity,
              routes: routes_to_submit,
              extra_revenue: @game.extra_revenue(entity, routes_to_submit) + (current_revenue - base_revenue),
              subsidy: @game.routes_subsidy(routes_to_submit)
            ))
          }
        elsif phase == :dividend
          dividend_options = step.respond_to?(:dividend_options) ? step.dividend_options(entity).map(&:to_s) : []
          if actions.include?('payout') || dividend_options.include?('payout') || actions.include?('dividend')
            advance_disabled = false
            advance_color = '#28a745'
            advance_text_color = '#fff'
            advance_text = 'Pay Out Full'
            advance_action = lambda {
              process_action(Engine::Action::Dividend.new(
                entity,
                kind: 'payout',
                extra_revenue: current_revenue - base_revenue
              ))
            }
          end
        end

        has_abilities = entity && (@game.companies || []).any? do |c|
          next false if c.respond_to?(:closed?) && c.closed?

          is_owner = c.owner == entity ||
                     (entity.respond_to?(:owner) && c.owner && c.owner == entity.owner)
          next false unless is_owner

          abilities = (c.respond_to?(:all_abilities) ? c.all_abilities : []).dup
          abilities.concat(c.abilities || []) if c.respond_to?(:abilities)

          abilities.any? do |a|
            next false if a.respond_to?(:passive?) && a.passive?
            next false if a.respond_to?(:passive) && a.passive
            next false if a.respond_to?(:closed?) && a.closed?
            next false if a.respond_to?(:used?) && a.used?

            true
          end
        end

        zone_3 = h(:div, { style: { flex: '0 0 22%', display: 'flex', flexDirection: 'column', padding: '0.4rem', boxSizing: 'border-box', overflowY: 'auto', position: 'relative' } }, [
          h(:style, {}, '.cmd-company-wrapper:hover .cmd-company-tooltip { display: block !important; }'),

          h(:div, { style: { flex: '0 0 auto', width: '100%', marginBottom: '0.4rem' } }, [
            (render_zone3_abilities(entity) if has_abilities),
          ].compact),

      h(:div, { attrs: { class: 'cmd-undo-redo-wrapper' }, style: { width: '100%', marginBottom: '0.4rem' } }, [
            h(:style, {}, '
              .cmd-undo-redo-wrapper #history,
              .cmd-undo-redo-wrapper .history,
              .cmd-undo-redo-wrapper input,
              .cmd-undo-redo-wrapper button:not(#undo):not(#redo) {
                display: none !important;
              }
              .cmd-undo-redo-wrapper,
              .cmd-undo-redo-wrapper * {
                box-sizing: border-box !important;
              }
              .cmd-undo-redo-wrapper,
              .cmd-undo-redo-wrapper div,
              .cmd-undo-redo-wrapper #history_and_undo,
              .cmd-undo-redo-wrapper .history_and_undo {
                display: flex !important;
                flex-direction: row !important;
                flex-wrap: nowrap !important;
                align-items: center !important;
                justify-content: space-between !important;
                width: 100% !important;
                min-width: 100% !important;
                max-width: 100% !important;
                margin: 0 !important;
                padding: 0 !important;
                border: none !important;
                background: transparent !important;
                box-shadow: none !important;
              }
              .cmd-undo-redo-wrapper button#undo,
              .cmd-undo-redo-wrapper button#redo {
                display: inline-flex !important;
                flex: 0 0 3.5rem !important;
                width: 3.5rem !important;
                min-width: 3.5rem !important;
                max-width: 3.5rem !important;
                height: 1.45rem !important;
                min-height: 1.45rem !important;
                max-height: 1.45rem !important;
                justify-content: center !important;
                align-items: center !important;
                padding: 0 4px !important;
                font-size: 0.85rem !important;
                font-weight: bold !important;
                background-color: #f8f9fa !important;
                color: #212529 !important;
                border: 1px solid #ced4da !important;
                border-radius: 4px !important;
                cursor: pointer !important;
                margin: 0 !important;
                line-height: 1 !important;
                box-shadow: 0 1px 2px rgba(0,0,0,0.05) !important;
              }
              .cmd-undo-redo-wrapper button#undo:hover:not(:disabled),
              .cmd-undo-redo-wrapper button#redo:hover:not(:disabled) {
                background-color: #e9ecef !important;
                border-color: #adb5bd !important;
              }
              .cmd-undo-redo-wrapper button#undo:disabled,
              .cmd-undo-redo-wrapper button#redo:disabled {
                background-color: #f1f3f5 !important;
                color: #adb5bd !important;
                cursor: not-allowed !important;
                opacity: 0.6 !important;
                box-shadow: none !important;
              }
            '),
            h(HistoryAndUndo, last_action_id: last_action_id),
          ]),

          h(:div, { style: { width: '100%', marginTop: 'auto', display: 'flex', justifyContent: 'center' } }, [
            h(:button, {
              style: {
                width: '100%',
                height: '1.45rem',
                minHeight: '1.45rem',
                maxHeight: '1.45rem',
                padding: '0',
                fontSize: '0.85rem',
                fontWeight: 'bold',
                backgroundColor: advance_color,
                color: advance_text_color,
                border: 'none',
                borderRadius: '4px',
                cursor: advance_disabled ? 'not-allowed' : 'pointer',
                boxShadow: advance_disabled ? 'none' : '0 1px 3px rgba(0,0,0,0.1)',
                display: 'inline-flex',
                alignItems: 'center',
                justifyContent: 'center',
                lineHeight: '1',
              },
              attrs: { disabled: advance_disabled },
              on: { click: advance_action },
            }, advance_text),
          ]),
        ])

        # Automated route generator gate
        current_action_id = @game.raw_actions.size
        if phase == :run_routes && @last_routed_action_id != current_action_id
          store(:last_routed_action_id, current_action_id, skip: true)
          store(:cmd_router_running, true, skip: false)

          if @routes.empty?
            trains = @game.route_trains(entity) || []
            trains.each do |train|
              @routes << Engine::Route.new(@game, @game.phase, train, routes: @routes)
            end
            store(:routes, @routes, skip: true)
          end

          lambda {
            `setTimeout(function() {`
            begin
              router = Engine::AutoRouter.new(@game, ->(_msg) {})
              router.compute(
                entity,
                routes: @routes.reject { |r| r.respond_to?(:paths) && r.paths.empty? },
                path_timeout: 10_000,
                route_timeout: 10_000,
                callback: lambda do |computed_routes|
                            store(:routes, computed_routes, skip: true)
                            store(:cmd_router_running, false)
                          end
              )
            rescue StandardError
              store(:cmd_router_running, false)
              `console.warn('AutoRouter skipped layout matching: ' + e)`
            end
            `}, 100);`
          }.call
        end

        h(:div, { style: { display: 'flex', flexDirection: 'row', width: '100%', height: '100%', boxSizing: 'border-box', backgroundColor: '#fff' } }, [
          zone_1,
          zone_2,
          zone_3,
        ])
      end

      def render_buyable_companies(step, entity)
        return nil unless entity

        operating_player = if entity.respond_to?(:player?) && entity.player?
                             entity
                           elsif entity.respond_to?(:owner) && entity.owner
                             entity.owner
                           end

        return nil unless operating_player

        buy_company_step = nil
        if @game.round.respond_to?(:steps)
          buy_company_step = @game.round.steps.find do |s|
            s.respond_to?(:buyable_companies) || s.respond_to?(:can_buy_company?)
          end
        end
        buy_company_step ||= step

        all_companies = if buy_company_step.respond_to?(:buyable_companies)
                          buy_company_step.buyable_companies(entity) || []
                        elsif buy_company_step.respond_to?(:can_buy_company?) && @game.respond_to?(:companies)
                          @game.companies.select { |c| buy_company_step.can_buy_company?(entity, c) }
                        else
                          []
                        end

        companies = all_companies.reject { |c| c.respond_to?(:closed?) && c.closed? }.select do |c|
          c.owner && c.owner == operating_player && c.owner != entity
        end

        return nil if companies.empty?

        company_boxes = companies.map do |c|
          owner_name = c.owner&.name || 'Bank'
          next nil if c.owner == entity

          min_price = if buy_company_step.respond_to?(:min_price)
                        buy_company_step.min_price(c)
                      else
                        (c.respond_to?(:min_price) ? c.min_price : 1)
                      end

          max_price = if buy_company_step.respond_to?(:max_price)
                        buy_company_step.max_price(entity, c)
                      else
                        (if c.respond_to?(:max_price)
                           c.max_price
                         else
                           (entity.respond_to?(:cash) ? entity.cash : 0)
                         end)
                      end

          menu_storage_key = "cmd_buy_company_menu_#{c.id}"
          price_storage_key = "cmd_buy_company_price_#{c.id}"

          company_click_handler = lambda {
            Lib::Storage[menu_storage_key] = true
            Lib::Storage[price_storage_key] = entity.respond_to?(:cash) ? entity.cash : 0
            update
          }

          menu_dropdown = nil
          if Lib::Storage[menu_storage_key]
            menu_title = "Buy #{c.name} from #{owner_name} (#{min_price}-#{max_price}):"

            confirm_handler = lambda {
              price_value = Lib::Storage[price_storage_key].to_i
              price_value = min_price if price_value < min_price
              price_value = max_price if price_value > max_price

              Lib::Storage[menu_storage_key] = nil
              Lib::Storage[price_storage_key] = nil
              process_action(Engine::Action::BuyCompany.new(
                entity,
                company: c,
                price: price_value
              ))
            }

            cancel_handler = lambda {
              Lib::Storage[menu_storage_key] = nil
              Lib::Storage[price_storage_key] = nil
              update
            }

            menu_dropdown = h(:div, {
                                style: {
                                  position: 'fixed',
                                  top: '50%',
                                  left: '50%',
                                  transform: 'translate(-50%, -50%)',
                                  backgroundColor: '#ffffff',
                                  border: '2px solid #333333',
                                  borderRadius: '8px',
                                  padding: '1.5rem',
                                  zIndex: '10000',
                                  boxShadow: '0px 10px 30px rgba(0,0,0,0.5)',
                                  color: '#000000',
                                  minWidth: '250px',
                                  textAlign: 'center',
                                },
                              }, [
              h(:div, { style: { fontSize: '0.85rem', fontWeight: 'bold', marginBottom: '0.8rem', whiteSpace: 'nowrap' } }, menu_title),
              h(:input, {
                  key: price_storage_key,
                  style: {
                    display: 'block',
                    width: '100%',
                    marginBottom: '0.8rem',
                    boxSizing: 'border-box',
                    padding: '5px 8px',
                    fontSize: '1rem',
                  },
                  props: {
                    value: Lib::Storage[price_storage_key] || min_price.to_s,
                  },
                  attrs: {
                    type: 'number',
                    min: min_price.to_s,
                    max: max_price.to_s,
                  },
                  on: {
                    input: lambda { |event|
                      Lib::Storage[price_storage_key] = `#{event}.target.value`
                      update
                    },
                  },
                }),
              h(:button, {
                  style: {
                    display: 'block',
                    width: '100%',
                    marginBottom: '0.2rem',
                    cursor: 'pointer',
                    fontSize: '0.75rem',
                    fontWeight: 'bold',
                    padding: '3px 6px',
                    backgroundColor: '#007bff',
                    border: '1px solid #0056b3',
                    color: '#ffffff',
                    borderRadius: '3px',
                  },
                  on: { click: confirm_handler },
                }, 'Confirm'),
              h(:button, {
                  style: {
                    display: 'block',
                    width: '100%',
                    cursor: 'pointer',
                    fontSize: '0.75rem',
                    padding: '3px 6px',
                    backgroundColor: '#e0e0e0',
                    border: '1px solid #999',
                    borderRadius: '3px',
                  },
                  on: { click: cancel_handler },
                }, 'Cancel'),
            ])
          end

          card_text = (c.sym || c.name).to_s

          card_props = {
            attrs: { class: 'game-card clickable action-buy' },
            style: {
              border: '2px solid #28a745',
              minWidth: '3.5rem',
              height: '1.45rem',
              padding: '0 4px',
              margin: '2px',
              boxSizing: 'border-box',
            },
            on: { click: company_click_handler },
          }

          desc_text = if c.respond_to?(:desc) && c.desc && !c.desc.empty?
                        c.desc
                      elsif c.respond_to?(:abilities) && c.abilities&.any?
                        c.abilities.map { |a| a.respond_to?(:description) ? a.description : nil }.compact.join(' ')
                      else
                        'No special abilities.'
                      end

          value_str = @game.format_currency(c.value || 0)
          revenue_str = @game.format_currency(c.revenue || 0)

          tooltip_card = render_company_tooltip('Private Company', c.name, desc_text, value_str, revenue_str, owner_name)

          h(:div, {
            attrs: { class: 'cmd-company-wrapper' },
            style: { display: 'inline-block', position: 'relative' },
          }, [
            tooltip_card,
            h(:div, card_props, card_text),
            menu_dropdown,
          ].compact)
        end.compact

        return nil if company_boxes.empty?

        render_action_row('Buy Privates:', [
          h(:style, {}, '.cmd-company-wrapper:hover .cmd-company-tooltip { display: block !important; }'),
          *company_boxes,
        ])
      end

      def render_discard_trains(step, entity)
          return nil unless entity && step

          train_boxes = []
          discardable = if step.respond_to?(:discardable_trains)
                          step.discardable_trains(entity)
                        elsif entity.respond_to?(:trains)
                          entity.trains
                        else
                          []
                        end

          (discardable || []).each do |train|
            click_handler = lambda {
              process_action(Engine::Action::DiscardTrain.new(
                entity,
                train: train
              ))
            }

            card_props = {
              attrs: { class: 'game-card clickable action-sell' },
              style: {
                border: '2px solid #dc2626',
                minWidth: '3.5rem',
                height: '1.45rem',
                padding: '0 4px',
                margin: '2px',
                boxSizing: 'border-box',
                cursor: 'pointer',
              },
              on: { click: click_handler },
            }
train_boxes << h(:div, card_props, train.name)
          end

          return nil if train_boxes.empty?
          render_action_row('Discard:', train_boxes)
        end

        def render_surrender_trains(actions, step, entity)
          return nil unless entity && step

          train_boxes = []
          trains = if step.respond_to?(:scrappable_trains)
                     step.scrappable_trains(entity)
                   elsif step.respond_to?(:surrenderable_trains)
                     step.surrenderable_trains(entity)
                   elsif step.respond_to?(:trains)
                     step.trains(entity)
                   elsif entity.respond_to?(:trains)
                     entity.trains
                   else
                     []
                   end

          action_class = if actions.include?('surrender_train')
                           Engine::Action::SurrenderTrain
                         elsif actions.include?('surrender')
                           Engine::Action::Surrender
                         else
                           Engine::Action::ScrapTrain
                         end

          (trains || []).each do |train|
            click_handler = lambda {
              process_action(action_class.new(
                entity,
                train: train
              ))
            }

            card_props = {
              attrs: { class: 'game-card clickable action-sell' },
              style: {
                border: '2px solid #dc2626',
                minWidth: '3.5rem',
                height: '1.45rem',
                padding: '0 4px',
                margin: '2px',
                boxSizing: 'border-box',
                cursor: 'pointer',
              },
              on: { click: click_handler },
            }

            btn_text = if step.respond_to?(:button_text)
                         step.button_text(train)
                       elsif step.respond_to?(:surrender_button_text)
                         step.surrender_button_text(train)
                       elsif step.respond_to?(:scrap_button_text)
                         step.scrap_button_text(train)
                       end

            cost_str = ''
            if btn_text
              if (m = btn_text.match(/\(([^)]+)\)/))
                cost_str = " (#{m[1]})"
              elsif (m = btn_text.match(/([+-]?\d+[\w]*)/))
                cost_str = " (#{m[1]})"
              end
            end

            if cost_str.empty?
              cost = nil
              if step.respond_to?(:surrender_cost)
                cost = step.surrender_cost(train)
              elsif step.respond_to?(:cost)
                cost = step.cost(train)
              elsif step.respond_to?(:scrap_cost)
                cost = step.scrap_cost(train)
              elsif @game.respond_to?(:surrender_cost)
                cost = @game.surrender_cost(train)
              elsif @game.respond_to?(:scrap_cost)
                cost = @game.scrap_cost(train)
              end

              if cost && !cost.zero?
                formatted_cost = @game.format_currency(cost)
                cost_str = " (#{formatted_cost})"
              end
            end

            train_boxes << h(:div, { style: { display: 'inline-flex', alignItems: 'center', gap: '0.25rem' } }, [
              h(:div, card_props, train.name),
              (cost_str.empty? ? nil : h(:span, { style: { fontSize: '0.85rem', color: '#555', whiteSpace: 'nowrap' } }, cost_str)),
            ].compact)
          end

          return nil if train_boxes.empty?
          render_action_row('Surrender:', train_boxes)
        end


      def render_buyable_trains(step, entity)
        return nil unless entity && step

        operating_player = if entity.respond_to?(:player?) && entity.player?
                             entity
                           elsif entity.respond_to?(:owner) && entity.owner
                             entity.owner
                           end

        train_boxes = []

        # 1. Depot / Bank Trains
        depot = @game.depot
        if depot
          buyable_depot = if step.respond_to?(:buyable_trains)
                            step.buyable_trains(entity).select do |t|
                              (t.respond_to?(:from_depot?) && t.from_depot?) ||
                                t.owner == depot ||
                                depot.upcoming.include?(t) ||
                                depot.discarded.include?(t)
                            end
                          else
                            [depot.upcoming.first, *depot.discarded].compact
                          end

          buyable_depot = [depot.upcoming.first].compact if buyable_depot.empty?
          unique_depot_trains = buyable_depot.uniq(&:name)

          unique_depot_trains.each do |train|
            variants = if train.respond_to?(:names_to_prices) && train.names_to_prices && !train.names_to_prices.empty?
                         train.names_to_prices
                       else
                         { train.name => train.price }
                       end

            variants.each do |variant_name, price|
              can_afford = (entity.respond_to?(:cash) ? entity.cash : 0) >= price ||
                           (entity.respond_to?(:trains) && entity.trains.empty?)

              variant_str = variant_name.to_s
              variant_param = (variant_str == train.name.to_s ? nil : variant_str)

              click_handler = lambda {
                process_action(Engine::Action::BuyTrain.new(
                  entity,
                  train: train,
                  price: price,
                  variant: variant_param
                ))
              }

              card_props = {
                attrs: { class: "game-card #{'clickable action-buy' if can_afford}" },
                style: {
                  border: '2px solid #28a745',
                  minWidth: '3.5rem',
                  height: '1.45rem',
                  padding: '0 4px',
                  margin: '2px',
                  boxSizing: 'border-box',
                  cursor: can_afford ? 'pointer' : 'not-allowed',
                  opacity: can_afford ? '1' : '0.6',
                },
                on: can_afford ? { click: click_handler } : {},
              }

              train_boxes << h(:div, { style: { display: 'inline-flex', alignItems: 'center', gap: '0.25rem', position: 'relative' } }, [
                h(:div, card_props, variant_str),
                h(:span, { style: { fontSize: '0.85rem', color: '#555', whiteSpace: 'nowrap' } }, "(from Bank for #{@game.format_currency(price)})"),
              ])
            end
          end
        end

        # 2. Other Corporate Trains (owned by same player or valid by step)
        other_corps = (@game.corporations + (@game.respond_to?(:minors) ? (@game.minors || []) : [])).reject { |c| c == entity }
        other_corps = other_corps.select { |c| c.owner && c.owner == operating_player } if operating_player

        other_corps.each do |c|
          (c.trains || []).each do |t|
            can_buy_train = if step.respond_to?(:can_buy_train?)
                              step.can_buy_train?(entity, t)
                            else
                              true
                            end
            next unless can_buy_train

            min_price = 1
            max_price = if step.respond_to?(:max_price)
                          step.max_price(entity, t)
                        else
                          (entity.respond_to?(:cash) ? entity.cash : 9999)
                        end

            menu_storage_key = "cmd_buy_corp_train_menu_#{c.id}_#{t.id}"
            price_storage_key = "cmd_buy_corp_train_price_#{c.id}_#{t.id}"

            train_click_handler = lambda {
              Lib::Storage[menu_storage_key] = true
              Lib::Storage[price_storage_key] = min_price
              update
            }

            menu_dropdown = nil
            if Lib::Storage[menu_storage_key]
              menu_title = "Buy #{t.name} from #{c.name} (#{min_price}-#{max_price}):"

              confirm_handler = lambda {
                price_value = Lib::Storage[price_storage_key].to_i
                price_value = min_price if price_value < min_price
                price_value = max_price if price_value > max_price

                Lib::Storage[menu_storage_key] = nil
                Lib::Storage[price_storage_key] = nil
                process_action(Engine::Action::BuyTrain.new(
                  entity,
                  train: t,
                  price: price_value
                ))
              }

              cancel_handler = lambda {
                Lib::Storage[menu_storage_key] = nil
                Lib::Storage[price_storage_key] = nil
                update
              }

              menu_dropdown = h(:div, {
                                  style: {
                                    position: 'fixed',
                                    top: '50%',
                                    left: '50%',
                                    transform: 'translate(-50%, -50%)',
                                    backgroundColor: '#ffffff',
                                    border: '2px solid #333333',
                                    borderRadius: '8px',
                                    padding: '1.5rem',
                                    zIndex: '10000',
                                    boxShadow: '0px 10px 30px rgba(0,0,0,0.5)',
                                    color: '#000000',
                                    minWidth: '250px',
                                    textAlign: 'center',
                                  },
                                }, [
                h(:div, { style: { fontSize: '0.85rem', fontWeight: 'bold', marginBottom: '0.8rem', whiteSpace: 'nowrap' } }, menu_title),
                h(:input, {
                    key: price_storage_key,
                    style: {
                      display: 'block',
                      width: '100%',
                      marginBottom: '0.8rem',
                      boxSizing: 'border-box',
                      padding: '5px 8px',
                      fontSize: '1rem',
                    },
                    props: {
                      value: Lib::Storage[price_storage_key] || min_price.to_s,
                    },
                    attrs: {
                      type: 'number',
                      min: min_price.to_s,
                      max: max_price.to_s,
                    },
                    on: {
                      input: lambda { |event|
                        Lib::Storage[price_storage_key] = `#{event}.target.value`
                        update
                      },
                    },
                  }),
                h(:button, {
                    style: {
                      display: 'block',
                      width: '100%',
                      marginBottom: '0.2rem',
                      cursor: 'pointer',
                      fontSize: '0.75rem',
                      fontWeight: 'bold',
                      padding: '3px 6px',
                      backgroundColor: '#007bff',
                      border: '1px solid #0056b3',
                      color: '#ffffff',
                      borderRadius: '3px',
                    },
                    on: { click: confirm_handler },
                  }, 'Confirm'),
                h(:button, {
                    style: {
                      display: 'block',
                      width: '100%',
                      cursor: 'pointer',
                      fontSize: '0.75rem',
                      padding: '3px 6px',
                      backgroundColor: '#e0e0e0',
                      border: '1px solid #999',
                      borderRadius: '3px',
                    },
                    on: { click: cancel_handler },
                  }, 'Cancel'),
              ])
            end

            card_props = {
              attrs: { class: 'game-card clickable action-buy' },
              style: {
                border: '2px solid #28a745',
                minWidth: '3.5rem',
                height: '1.45rem',
                padding: '0 4px',
                margin: '2px',
                boxSizing: 'border-box',
              },
              on: { click: train_click_handler },
            }

            train_boxes << h(:div, { style: { display: 'inline-flex', alignItems: 'center', gap: '0.25rem', position: 'relative' } }, [
              h(:div, card_props, t.name),
              h(:span, { style: { fontSize: '0.85rem', color: '#555', whiteSpace: 'nowrap' } }, "(from #{c.id || c.name})"),
              menu_dropdown,
            ].compact)
          end
        end

        return nil if train_boxes.empty?

        render_action_row('Buy Train:', train_boxes)
      end

def render_issue_shares(step, entity)
        entity ||= current_entity
        return nil unless entity && step

        issuable_bundles = begin
          if step.respond_to?(:issuable_shares)
            begin
              step.issuable_shares(entity)
            rescue ArgumentError
              step.issuable_shares
            end
          elsif step.respond_to?(:issuable_bundles)
            begin
              step.issuable_bundles(entity)
            rescue ArgumentError
              step.issuable_bundles
            end
          elsif @game.respond_to?(:issuable_shares)
            @game.issuable_shares(entity)
          elsif step.respond_to?(:bundles_for_corporation)
            begin
              step.bundles_for_corporation(entity, entity)
            rescue ArgumentError
              step.bundles_for_corporation(entity)
            end
          elsif step.respond_to?(:bundles)
            step.bundles(entity)
          else
            []
          end
        rescue StandardError => e
          `console.warn('DCC issuable_bundles error: ' + e)`
          []
        end || []

        `console.log('DCC render_issue_shares:', {
          entity: #{entity.id},
          step: #{step.class.name},
          bundle_count: #{issuable_bundles.size},
          bundles: #{issuable_bundles.to_n}
        })`

        rows = []

        if issuable_bundles.any?
          issue_buttons = issuable_bundles.map do |raw_bundle|
            bundle = raw_bundle.respond_to?(:to_bundle) && !raw_bundle.respond_to?(:num_shares) ? raw_bundle.to_bundle : raw_bundle
            num = if bundle.respond_to?(:num_shares)
                    bundle.num_shares
                  elsif bundle.respond_to?(:shares)
                    bundle.shares.size
                  else
                    1
                  end

            price = if bundle.respond_to?(:price)
                      bundle.price
                    elsif bundle.respond_to?(:share_price) && bundle.share_price
                      bundle.share_price.price * num
                    elsif entity.respond_to?(:share_price) && entity.share_price
                      entity.share_price.price * num
                    else
                      0
                    end

           pct_str = if bundle.respond_to?(:percent) && bundle.percent
                        "#{bundle.percent}%"
                      else
                        "#{num}S"
                      end
            price_str = "(#{@game.format_currency(price)})"

            click_handler = lambda {
              actions = begin
                          @game.round.actions_for(entity)
                        rescue StandardError
                          []
                        end || []
              if actions.include?('issue_shares')
                process_action(Engine::Action::IssueShares.new(
                  entity,
                  bundle: bundle
                ))
              elsif actions.include?('corporate_sell_shares')
                process_action(Engine::Action::CorporateSellShares.new(
                  entity,
                  bundle: bundle
                ))
              else
                process_action(Engine::Action::SellShares.new(
                  entity,
                  shares: bundle.respond_to?(:shares) ? bundle.shares : [bundle],
                  share_price: bundle.respond_to?(:share_price) ? bundle.share_price : entity.share_price,
                  percent: bundle.respond_to?(:percent) ? bundle.percent : 10
                ))
              end
            }

            card_props = {
              attrs: { class: 'game-card clickable action-sell' },
              style: {
                border: '2px solid #dc2626',
                minWidth: '2.5rem',
                height: '1.45rem',
                padding: '0 4px',
                margin: '0',
                boxSizing: 'border-box',
                cursor: 'pointer',
                fontSize: '0.82rem',
                fontWeight: 'bold',
              },
            }

            h(:div, {
              style: {
                display: 'inline-flex',
                alignItems: 'center',
                gap: '0.2rem',
                cursor: 'pointer',
                margin: '1px 2px',
              },
              on: { click: click_handler },
            }, [
              h(:div, card_props, pct_str),
              h(:span, { style: { fontSize: '0.82rem', color: '#444', fontWeight: 'bold', whiteSpace: 'nowrap' } }, price_str),
            ])
          end
          rows << render_action_row('Issue:', issue_buttons)
        elsif (@game.round.actions_for(entity) || []).include?('issue_shares')
          `console.warn('DCC: issue_shares is in actions, but 0 bundles were found.')`
          rows << render_action_row('Issue:', [
            h(:span, { style: { color: '#888', fontStyle: 'italic', fontSize: '0.85rem' } }, 'No issuable shares available')
          ])
        end
        redeemable_bundles = if step.respond_to?(:redeemable_shares)
                               step.redeemable_shares(entity) || []
                             elsif step.respond_to?(:redeemable_bundles)
                               step.redeemable_bundles(entity) || []
                             elsif step.respond_to?(:buyable_shares)
                               step.buyable_shares(entity) || []
                             else
                               []
                             end

        if redeemable_bundles.any?
          redeem_buttons = redeemable_bundles.map do |bundle|
           num = bundle.num_shares
            price = bundle.price
            pct_str = if bundle.respond_to?(:percent) && bundle.percent
                        "#{bundle.percent}%"
                      else
                        "#{num}S"
                      end
            price_str = "(#{@game.format_currency(price)})"

            click_handler = lambda {
              actions = begin
                          @game.round.actions_for(entity)
                        rescue StandardError
                          []
                        end || []
              action_class = actions.include?('corporate_buy_shares') ? Engine::Action::CorporateBuyShares : Engine::Action::BuyShares
              process_action(action_class.new(
                entity,
                shares: bundle.shares,
                share_price: bundle.share_price || (bundle.price / bundle.num_shares),
                percent: bundle.percent
              ))
            }

            card_props = {
              attrs: { class: 'game-card clickable action-buy' },
              style: {
                border: '2px solid #28a745',
                minWidth: '2.5rem',
                height: '1.45rem',
                padding: '0 4px',
                margin: '0',
                boxSizing: 'border-box',
                cursor: 'pointer',
                fontSize: '0.82rem',
                fontWeight: 'bold',
              },
            }

            h(:div, {
              style: {
                display: 'inline-flex',
                alignItems: 'center',
                gap: '0.2rem',
                cursor: 'pointer',
                margin: '1px 2px',
              },
              on: { click: click_handler },
            }, [
              h(:div, card_props, pct_str),
              h(:span, { style: { fontSize: '0.82rem', color: '#444', fontWeight: 'bold', whiteSpace: 'nowrap' } }, price_str),
            ])
          end
          rows << render_action_row('Redeem:', redeem_buttons)
        end

        return nil if rows.empty?

        h(:div, { style: { display: 'flex', flexDirection: 'column', gap: '0.35rem', width: '100%' } }, rows.compact)
      end

      def render_ground_truth_actions(actions, step)
        return h(:div) if @game.finished

        return h(UpgradeOrDiscardTrains) if actions.include?('discard_train') && actions.include?('swap_train')

        if actions.include?('par') && step&.respond_to?(:corporation_pending_par) && step&.corporation_pending_par
          return h(CorporationPendingPar, corporation: step.corporation_pending_par)
        end

        if actions.include?('par') && step&.respond_to?(:corporation_pending_par) && step&.corporation_pending_par
          return h(CorporationPendingPar, corporation: step.corporation_pending_par)
        end

        case @game.round
        when Engine::Round::Stock
          h(::View::Game::DashboardStock, game: @game)
        when Engine::Round::Operating
          if actions.include?('merge')
            h(Round::Merger, game: @game)
          elsif actions.include?('buy_shares') && step&.current_entity&.player?
            h(::View::Game::DashboardStock, game: @game)
          elsif actions.include?('bid')
            h(Round::Auction, game: @game, user: nil)
          else
            components = []

            convert_track = step&.respond_to?(:conversion?) && step&.conversion?
            loans_rendered = false

            components << h(SpecialBuy) if actions.include?('special_buy')
            components << h(TrackConversion) if actions.include?('run_routes') && convert_track
            components << h(Convert) if actions.include?('convert')
            components << h(SwitchTrains) if actions.include?('switch_trains')
            components << h(ReassignTrains) if actions.include?('reassign_trains')
            components << h(DoubleHeadTrains) if actions.include?('double_head_trains')
            components << h(CombinedTrains) if actions.include?('combined_trains')
            components << h(Choose) if actions.include?('choose')
            components << h(BuyToken, entity: step&.current_entity) if actions.include?('buy_token')

    if actions.include?('issue_shares')
              components << render_issue_shares(step, step&.current_entity || current_entity)
            end

            if actions.include?('buy_train') || actions.include?('sell_train')
              components << render_issue_shares(step, step&.current_entity || current_entity) if actions.include?('sell_shares') || actions.include?('buy_shares')
            elsif actions.include?('buy_power')
              components << render_issue_shares(step, step&.current_entity || current_entity) if actions.include?('sell_shares')
              components << h(BuyPower)
            elsif actions.include?('borrow_train')
              components << h(BorrowTrain)
            elsif step&.respond_to?(:cash_crisis?) && step&.cash_crisis?
              components << h(CashCrisis)
              loans_rendered = true if (%w[take_loan payoff_loan] & actions).any?
            elsif actions.include?('buy_shares') || actions.include?('sell_shares') || actions.include?('par')
              if step&.respond_to?(:price_protection) && (price_protection = step.price_protection)
                components << h(Corporation, corporation: price_protection.corporation)
                components << h(BuySellShares, corporation: price_protection.corporation)
              elsif @game.corporations_can_ipo?
                components << h(CorporateBuySellShares)
              else
                components << render_issue_shares(step, step&.current_entity || current_entity)
              end
              components << h(CorporateBuyShares)
            elsif actions.include?('corporate_sell_shares')
              components << h(CorporateSellShares)
            elsif actions.include?('swap_train')
              components << h(SwapTrain)
            elsif actions.include?('buy_corporation')
              components << h(BuyCorporation)
            end


            if actions.include?('scrap_train') || actions.include?('surrender_train') || actions.include?('surrender')
              components << render_surrender_trains(actions, step, step&.current_entity)
            end
            components << h(Loans, corporation: step&.current_entity) if !loans_rendered && (%w[take_loan payoff_loan] & actions).any?
            components << h(ViewMergeOptions, corporation: step&.current_entity) if actions.include?('view_merge_options')

            if actions.include?('bankrupt')
              entity = step&.current_entity
              player = entity&.player? ? entity : entity&.owner

              show_bankrupt = false
              if step&.respond_to?(:must_buy_train?) && step&.must_buy_train?(entity)
                show_bankrupt = @game.respond_to?(:can_go_bankrupt?) ? @game.can_go_bankrupt?(player, entity) : true
              elsif @game.round.respond_to?(:stock?) && @game.round.stock? && step&.respond_to?(:must_sell?) && step&.must_sell?(player)
                show_bankrupt = true
              end

              if show_bankrupt
                b_options = @game.respond_to?(:bankruptcy_options) ? @game.bankruptcy_options(player) : []

                if b_options.empty?
                  components << h(:button, {
                                    style: { width: '100%', padding: '0.5rem', backgroundColor: '#dc3545', color: 'white', fontWeight: 'bold', border: 'none', borderRadius: '4px', cursor: 'pointer' },
                                    on: { click: -> { process_action(Engine::Action::Bankrupt.new(entity)) } },
                                  }, 'Declare Bankruptcy')
                else
                  b_options.each do |opt|
                    btn_text = @game.respond_to?(:bankruptcy_button_text) ? @game.bankruptcy_button_text(opt) : 'Declare Bankruptcy'
                    components << h(:button, {
                                      style: { width: '100%', padding: '0.5rem', backgroundColor: '#dc3545', color: 'white', fontWeight: 'bold', border: 'none', borderRadius: '4px', cursor: 'pointer', marginBottom: '0.2rem' },
                                      on: { click: -> { process_action(Engine::Action::Bankrupt.new(entity, option: opt)) } },
                                    }, btn_text)
                  end
                end
              end
            end

            if actions.include?('buy_company')
              components << render_buyable_companies(step, step&.current_entity)
            end
                        if actions.include?('buy_train')
              components << render_buyable_trains(step, step&.current_entity)
            end
            if actions.include?('discard_train')
              components << render_discard_trains(step, step&.current_entity)
            end

            components << h(AcquireCompanies) if actions.include?('acquire_company')
            components << h(CorporateSellCompanies) if actions.include?('corporate_sell_company')
            components << h(CorporateBuyCompanies) if actions.include?('corporate_buy_company')

            h(:div, { style: { display: 'flex', flexDirection: 'column', gap: '0.55rem', width: '100%', alignItems: 'center' } }, components.compact)
          end
        when Engine::Round::Choices
          h(Round::Choices, game: @game)
        when Engine::Round::Auction, Engine::Round::Draft
          h(Round::Auction, game: @game, user: nil)
        when Engine::Round::Merger
          if !(%w[buy_train scrap_train reassign_trains] & actions).empty? && @game.train_actions_always_use_operating_round_view?
            h(Round::Operating, game: @game)
          else
            h(Round::Merger, game: @game)
          end
        else
          if @game.round.stock?
            h(::View::Game::DashboardStock, game: @game)
          elsif @game.round.unordered?
            h(Round::Unordered, game: @game, user: nil)
          else
            h(:div)
          end
        end
      end
    end
  end
end

# rubocop:enable Layout/LineLength