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
require 'view/game/dashboard/railcard_helper'

module View
  module Game
    class DashboardCommandColumn < Snabberb::Component
      include Actionable
      include Lib::Settings
include View::Game::Dashboard::RailcardHelper
      FONT_MONEY = '"Courier New", Courier, monospace'
      COLOR_MONEY = '#4c1d95'

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
        is_arr = `Array.isArray(#{children})`
        items = (is_arr ? children : [children]).compact
        return nil if items.empty?

        h(:div, {
          style: {
            display: 'flex',
            flexDirection: 'row',
            alignItems: 'center',
            justifyContent: 'flex-start',
            gap: '0.4rem',
            width: '100%',
            maxWidth: '100%',
            margin: '0 auto',
          },
        }, [
          h(:span, { style: { fontSize: '0.92rem', fontWeight: 'bold', color: '#333', minWidth: '6.5rem', textAlign: 'left', flexShrink: '0' } }, label),
          h(:div, { style: { display: 'flex', flexDirection: 'row', flexWrap: 'nowrap', alignItems: 'center', gap: '0.3rem', overflowX: 'auto', maxWidth: '100%' } }, items),
        ])
      end




# render_railcard extracted to View::Game::Dashboard::RailcardHelper  

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
          card_text = (c.sym || c.name).to_s

          click_handler = lambda {
            c_actions = begin
                          @game.round.actions_for(c)
                        rescue StandardError
                          []
                        end || []

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
                rescue StandardError
                end
              end
            end
          }

          render_railcard(card_text, ['game-card', 'action-buy', 'clickable'], click_handler, build_company_tooltip(c))
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
          h(:span, { style: { fontSize: '0.92rem', fontWeight: 'bold', color: '#333', flexShrink: '0' } }, 'Abilities:'),
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
     elsif actions.include?('par') && (
          (step&.respond_to?(:corporation_pending_par) && step.corporation_pending_par) ||
          (step&.respond_to?(:corporation) && step.corporation) ||
          (step&.respond_to?(:par_corporation) && step.par_corporation) ||
          (step&.respond_to?(:corporations) && step.corporations&.one?) ||
          (step&.current_entity || current_entity)&.corporation?
        )
        phase = :par

        elsif actions.include?('corporate_buy_shares') || actions.include?('buy_shares')
          phase = :buy_shares
        elsif actions.include?('bid')
          phase = :bid
        elsif actions.include?('merge') || actions.include?('convert')
          phase = :merge
        elsif actions.include?('take_loan') || actions.include?('payoff_loan')
          phase = :loan
        end

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
          rescue Engine::GameError, StandardError
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
            bid: 'AUCTION',
            par: 'PAR PRICE',
            merge: 'MERGER',
            loan: 'LOAN',
            buy_shares: 'BUY SHARES',
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

        zone_2_content = []

        if phase == :run_routes
          if @cmd_router_running
            zone_2_content << h(:div, { style: { padding: '0.2rem', textAlign: 'center', color: '#666', fontStyle: 'italic', fontSize: '0.9rem' } }, '🔄 Computing optimal network tracks...')
          else
            zone_2_content << render_action_row('Revenue:', [
              h(:button, { style: { width: '1.8rem', height: '1.8rem', fontSize: '1.1rem', fontWeight: 'bold', cursor: 'pointer', backgroundColor: '#e0e0e0', border: '1px solid #999', borderRadius: '4px', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', padding: '0', lineHeight: '1' }, on: { click: -> { Lib::Storage[storage_key] = [current_revenue - 10, 0].max; update } } }, '-'),
h(:div, { style: { fontSize: '1.2rem', fontWeight: 'bold', color: COLOR_MONEY, fontFamily: FONT_MONEY, minWidth: '4.5rem', textAlign: 'center', height: '1.8rem', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', lineHeight: '1' } }, formatted_revenue),
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
        zone_2 = h(:div, { style: { flex: '1 1 56%', display: 'flex', flexDirection: 'column', alignItems: 'flex-start', justifyContent: 'flex-start', gap: '0.25rem', padding: '0.25rem 0.5rem', borderRight: '1px solid #ccc', boxSizing: 'border-box', overflowY: 'auto' } }, zone_2_content.compact)

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
          when :par then advance_text = 'Skip Par'
          when :merge then advance_text = 'Done / Pass'
          when :loan then advance_text = 'Done / Pass'
          when :buy_shares then advance_text = 'Done / Pass'
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

          h(:div, { style: { flex: '0 0 auto', width: '100%', marginBottom: '0.3rem' } }, [
            (render_zone3_abilities(entity) if has_abilities),
          ].compact),

          h(:div, { style: { width: '100%', marginTop: 'auto', display: 'flex', flexDirection: 'column', gap: '0.35rem', alignItems: 'center' } }, [
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

            h(:div, { attrs: { class: 'cmd-undo-redo-wrapper' }, style: { width: '100%' } }, [
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
                  justify-content: flex-start !important;
                  gap: 0.6rem !important;
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
          ]),
        ])

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

      def render_merger_step(step, entity, actions)
        return nil unless entity && step

        components = []
        top_buttons = []

        if actions.include?('convert')
          top_buttons << h(:button, {
            style: { padding: '0.3rem 0.6rem', fontSize: '0.9rem', fontWeight: 'bold', backgroundColor: '#2563eb', color: '#fff', border: 'none', borderRadius: '4px', cursor: 'pointer' },
            on: { click: -> { process_action(Engine::Action::Convert.new(entity)) } },
          }, 'Convert')
        end

        show_merge = Lib::Storage['show_merge_candidates'] || !actions.include?('convert')

        if actions.include?('merge')
          top_buttons << h(:button, {
            style: { padding: '0.3rem 0.6rem', fontSize: '0.9rem', fontWeight: 'bold', backgroundColor: show_merge ? '#16a34a' : '#2563eb', color: '#fff', border: 'none', borderRadius: '4px', cursor: 'pointer' },
            on: { click: -> { Lib::Storage['show_merge_candidates'] = true; update } },
          }, 'Merge')
        end

        if actions.include?('take_loan')
          loan_amount = @game.respond_to?(:loan_value) ? @game.loan_value(entity) : (@game.loans.first&.amount || 0)
          btn_text = loan_amount.positive? ? "Take Loan (#{@game.format_currency(loan_amount)})" : 'Take Loan'
          top_buttons << h(:button, {
            style: { padding: '0.3rem 0.6rem', fontSize: '0.9rem', fontWeight: 'bold', fontFamily: loan_amount.positive? ? FONT_MONEY : 'inherit', backgroundColor: '#dc2626', color: '#fff', border: 'none', borderRadius: '4px', cursor: 'pointer' },
            on: { click: -> { process_action(Engine::Action::TakeLoan.new(entity, loan: @game.loans.first)) } },
          }, btn_text)
        end

        if actions.include?('payoff_loan')
          top_buttons << h(:button, {
            style: { padding: '0.3rem 0.6rem', fontSize: '0.9rem', fontWeight: 'bold', backgroundColor: '#2563eb', color: '#fff', border: 'none', borderRadius: '4px', cursor: 'pointer' },
            on: { click: -> { process_action(Engine::Action::PayoffLoan.new(entity, loan: entity.loans.first)) } },
          }, 'Payoff Loan')
        end

        components << render_action_row('Action:', top_buttons) if top_buttons.any?

        if actions.include?('merge') && show_merge
          mergeables = if step.respond_to?(:mergeable_candidates)
                         step.mergeable_candidates(entity)
                       elsif step.respond_to?(:mergeable)
                         step.mergeable(entity)
                       elsif step.respond_to?(:mergeable_entities)
                         step.mergeable_entities(entity)
                       else
                         []
                       end

          if mergeables.any?
            merge_boxes = mergeables.map do |target|
              click_handler = lambda {
                kwargs = {}
                if target.respond_to?(:minor?) && target.minor?
                  kwargs[:minor] = target
                else
                  kwargs[:corporation] = target
                end
                process_action(Engine::Action::Merge.new(entity, **kwargs))
              }
render_railcard(target.name, ['game-card', 'action-buy', 'clickable'], click_handler)
            end
            components << h(:div, { style: { fontSize: '0.85rem', fontWeight: 'bold', color: '#333', marginTop: '0.2rem', marginBottom: '0.2rem' } }, "Corporations that can merge with #{entity.name}:")
            components << h(:div, { style: { display: 'flex', flexDirection: 'row', flexWrap: 'wrap', gap: '0.3rem' } }, merge_boxes)
          end
        end

        if actions.include?('buy_shares') || actions.include?('corporate_buy_shares')
          buyable = if step.respond_to?(:buyable_shares)
                      step.buyable_shares(entity)
                    elsif step.respond_to?(:buyable_bundles)
                      step.buyable_bundles(entity)
                    elsif @game.respond_to?(:redeemable_shares)
                      @game.redeemable_shares(entity)
                    else
                      []
                    end

          if buyable.any?
            buy_boxes = buyable.map do |raw_bundle|
              bundle = raw_bundle.respond_to?(:to_bundle) && !raw_bundle.respond_to?(:num_shares) ? raw_bundle.to_bundle : raw_bundle
              num_shares = bundle.respond_to?(:num_shares) ? bundle.num_shares : (bundle.respond_to?(:shares) ? bundle.shares.size : 1)
              pct = bundle.respond_to?(:percent) ? bundle.percent : (num_shares * 10)
              price = bundle.respond_to?(:price) ? bundle.price : (bundle.respond_to?(:share_price) ? bundle.share_price.price * num_shares : 0)

              click_handler = lambda {
                action_class = actions.include?('corporate_buy_shares') ? Engine::Action::CorporateBuyShares : Engine::Action::BuyShares
                process_action(action_class.new(entity, shares: bundle.respond_to?(:shares) ? bundle.shares : [bundle], share_price: bundle.respond_to?(:share_price) ? bundle.share_price : nil, percent: pct))
              }
              corp = bundle.respond_to?(:corporation) ? bundle.corporation : entity
render_railcard("Buy #{pct}% (#{@game.format_currency(price)})", ['game-card', 'action-buy', 'clickable'], click_handler)
            end
            components << render_action_row('Buy Treasury Share:', buy_boxes)
          else
            components << render_action_row('Buy Treasury Share:', [h(:span, { style: { fontStyle: 'italic', color: '#666', fontSize: '0.85rem' } }, 'No shares available')])
          end
        end

        h(:div, { style: { display: 'flex', flexDirection: 'column', gap: '0.4rem', width: '100%' } }, components)
      end

      def render_bid(step, entity, actions, target = nil)
        target ||= if step.respond_to?(:auctioning) && step.auctioning
                     step.auctioning
                   elsif Lib::Storage['selected_bid_corp']
                     target_id = Lib::Storage['selected_bid_corp']
                     (@game.respond_to?(:companies) ? @game.companies.find { |c| c.id.to_s == target_id.to_s } : nil) ||
                       @game.corporations.find { |c| c.id.to_s == target_id.to_s } ||
                       (@game.respond_to?(:minors) ? @game.minors.find { |m| m.id.to_s == target_id.to_s } : nil)
                   elsif step.respond_to?(:companies) && step.companies&.one?
                     step.companies.first
                   end

        return render_action_row('Auction:', [h(:span, { style: { fontStyle: 'italic', color: '#666', fontSize: '0.85rem' } }, 'Select an available company to bid')]) unless target

        current_bidder = step.respond_to?(:current_entity) && step.current_entity ? step.current_entity : entity
        bidder_name = current_bidder&.name || 'Unknown'

        high_bid_obj = if step.respond_to?(:highest_bid)
                         step.highest_bid(target)
                       elsif step.respond_to?(:high_bid)
                         step.high_bid(target)
                       end

        high_bidder = if step.respond_to?(:high_bidder)
                        step.high_bidder(target)
                      elsif high_bid_obj.respond_to?(:entity)
                        high_bid_obj.entity
                      end

        high_bid_amount = if high_bid_obj.respond_to?(:price)
                            high_bid_obj.price
                          elsif high_bid_obj.is_a?(Numeric)
                            high_bid_obj
                          end

        high_bid_str = if high_bid_amount && high_bid_amount.positive?
                         bidder_tag = high_bidder ? " (#{high_bidder.name})" : ''
                         "#{@game.format_currency(high_bid_amount)}#{bidder_tag}"
                       else
                         'None'
                       end

        min_bid = if step.respond_to?(:min_bid)
                    begin
                      step.min_bid(target)
                    rescue ArgumentError
                      step.min_bid
                    end
                  elsif target.respond_to?(:min_bid)
                    target.min_bid
                  elsif target.respond_to?(:value)
                    target.value
                  else
                    100
                  end

        min_increment = if step.respond_to?(:min_increment)
                          step.min_increment
                        elsif @game.respond_to?(:min_bid_increment)
                          @game.min_bid_increment
                        else
                          5
                        end

        max_bid = if step.respond_to?(:max_bid)
                    begin
                      step.max_bid(current_bidder, target)
                    rescue ArgumentError
                      step.max_bid(current_bidder)
                    end
                  elsif current_bidder.respond_to?(:cash)
                    current_bidder.cash
                  else
                    999_999
                  end

        storage_key = "cmd_bid_price_#{target.id}"
        stored_val = Lib::Storage[storage_key]&.to_i
        current_bid = (stored_val && stored_val >= min_bid) ? stored_val : min_bid
card_text = target.respond_to?(:sym) && target.sym ? target.sym : target.name
        subtext = (target.respond_to?(:value) && target.value) ? @game.format_currency(target.value) : nil
        tooltip = target.respond_to?(:company?) && target.company? ? build_company_tooltip(target) : nil
        badge_label = subtext ? "#{card_text} #{subtext}" : card_text
        target_badge = render_railcard(badge_label, ['game-card'], nil, tooltip)
        
        cancel_btn = nil
        if Lib::Storage['selected_bid_corp'] && !(step.respond_to?(:auctioning) && step.auctioning)
          cancel_btn = h(:button, {
            style: {
              padding: '0 6px',
              height: '1.45rem',
              minHeight: '1.45rem',
              maxHeight: '1.45rem',
              fontSize: '0.75rem',
              backgroundColor: '#e0e0e0',
              border: '1px solid #999',
              borderRadius: '3px',
              cursor: 'pointer',
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              lineHeight: '1',
              boxSizing: 'border-box',
              margin: '0',
            },
            on: { click: lambda { Lib::Storage['selected_bid_corp'] = nil; update } },
          }, 'Cancel')
        end

        row1_items = [
          target_badge,
          h(:span, { style: { fontSize: '0.82rem', color: '#333' } }, [
            h(:b, 'High: '),
            h(:span, { style: { fontFamily: FONT_MONEY, fontWeight: 'bold', color: COLOR_MONEY } }, high_bid_str),
          ]),
          cancel_btn,
        ].compact

        can_afford = current_bid <= max_bid

        confirm_bid = lambda {
          Lib::Storage[storage_key] = nil
          Lib::Storage['selected_bid_corp'] = nil

          bid_args = { price: current_bid }
          if target.respond_to?(:corporation?) && target.corporation?
            bid_args[:corporation] = target
          elsif target.respond_to?(:company?) && target.company?
            bid_args[:company] = target
          elsif target.is_a?(Engine::Minor)
            bid_args[:minor] = target
          else
            bid_args[:entity] = target
          end

          process_action(Engine::Action::Bid.new(current_bidder, **bid_args))
        }
row2_items = [
          h(:input, {
            style: {
              width: '4.5rem',
              height: '1.45rem',
              minHeight: '1.45rem',
              maxHeight: '1.45rem',
              fontSize: '0.85rem',
              textAlign: 'center',
              boxSizing: 'border-box',
              border: '1px solid #999',
              borderRadius: '3px',
              fontFamily: FONT_MONEY,
              fontWeight: 'bold',
              color: COLOR_MONEY,
              padding: '0 4px',
              margin: '0',
              lineHeight: '1.45rem',
            },
            attrs: { type: 'number', min: min_bid.to_s, max: max_bid.to_s, step: min_increment.to_s },
            props: { value: current_bid.to_s },
            on: { input: lambda { |e| Lib::Storage[storage_key] = `#{e}.target.value`.to_i; update } },
          }),
          h(:button, {
            style: {
              height: '1.45rem',
              minHeight: '1.45rem',
              maxHeight: '1.45rem',
              padding: '0 8px',
              fontSize: '0.82rem',
              fontWeight: 'bold',
              fontFamily: FONT_MONEY,
              backgroundColor: can_afford ? '#28a745' : '#ccc',
              color: '#fff',
              border: 'none',
              borderRadius: '3px',
              cursor: can_afford ? 'pointer' : 'not-allowed',
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              lineHeight: '1',
              boxSizing: 'border-box',
              margin: '0',
            },
            attrs: { disabled: !can_afford },
            on: { click: confirm_bid },
          }, "Bid #{@game.format_currency(current_bid)}"),
        ]

        h(:div, { style: { display: 'flex', flexDirection: 'column', gap: '0.3rem', width: '100%' } }, [
          render_action_row('Auction:', row1_items),
          render_action_row('Your Bid:', row2_items),
        ])
      end

      def player_bid_for(step, item, player)
        return nil unless step && item && player

        if step.respond_to?(:bids) && step.bids
          bids_for_item = step.bids[item]
          if bids_for_item.is_a?(Array)
            found_bid = bids_for_item.find do |b|
              b_entity = b.respond_to?(:entity) ? b.entity : (b.is_a?(Hash) ? b[:entity] : nil)
              b_entity == player
            end
            if found_bid
              return found_bid.respond_to?(:price) ? found_bid.price : (found_bid.is_a?(Hash) ? found_bid[:price] : nil)
            end
          end
        end

        high_bid_obj = if step.respond_to?(:highest_bid)
                         step.highest_bid(item)
                       elsif step.respond_to?(:high_bid)
                         step.high_bid(item)
                       end
        high_bidder = if step.respond_to?(:high_bidder)
                        step.high_bidder(item)
                      elsif high_bid_obj.respond_to?(:entity)
                        high_bid_obj.entity
                      end

        if high_bidder == player
          if high_bid_obj.respond_to?(:price)
            return high_bid_obj.price
          elsif high_bid_obj.is_a?(Numeric)
            return high_bid_obj
          end
        end

        nil
      rescue StandardError
        nil
      end

      def render_par_step(step, entity, corporation)
        return h(:div) unless step && corporation

        par_nodes = if step.respond_to?(:get_par_prices_with_help)
                      step.get_par_prices_with_help(entity, corporation)
                    elsif step.respond_to?(:get_par_prices)
                      step.get_par_prices(entity, corporation)
                      elsif step.respond_to?(:par_prices)
                    begin
                      step.par_prices(entity, corporation)
                    rescue ArgumentError
                      step.par_prices(corporation)
                    end
                    elsif @game.respond_to?(:par_prices)
                      @game.par_prices(corporation)
                    else
                      @game.stock_market.par_prices
                    end

        if @game.respond_to?(:par_chart)
          par_nodes = par_nodes.reject do |node|
            p_obj = node.is_a?(Array) ? node.first : node
            slots = @game.par_chart[p_obj]
            slots && slots.none?(&:nil?)
          end
        end

corp_badge = render_railcard(corporation.name, ['game-card'])

        buttons = par_nodes.map do |node|
          price = node.is_a?(Array) ? node[0] : node
          help = node.is_a?(Array) ? node[1] : nil
          price_val = price.respond_to?(:price) ? price.price : price

          price_str = @game.format_currency(price_val)
          label = help ? "#{price_str} (#{help})" : price_str

          multiplier = if corporation.respond_to?(:presidents_percent) && corporation.respond_to?(:share_percent)
                         (corporation.presidents_percent / corporation.share_percent).to_i
                       elsif corporation.respond_to?(:shares) && corporation.shares.first&.president
                         corporation.shares.first.num_shares || 2
                       else
                         2
                       end
          cost = price_val * multiplier
          can_afford = (entity.respond_to?(:cash) ? entity.cash : 0) >= cost

          click_handler = lambda {
            slot = if @game.respond_to?(:par_chart) && @game.par_chart[price]
                     @game.par_chart[price].index(nil)
                   end

            args = {
              corporation: corporation,
              share_price: price,
            }
            args[:slot] = slot if slot

            process_action(Engine::Action::Par.new(entity, **args))
          }

          h(:button, {
            attrs: { disabled: !can_afford },
            style: {
              height: '1.45rem',
              padding: '0 8px',
              fontSize: '0.82rem',
              fontWeight: 'bold',
              fontFamily: FONT_MONEY,
              backgroundColor: can_afford ? '#f8f9fa' : '#e9ecef',
    color: can_afford ? COLOR_MONEY : '#9ca3af',
              border: can_afford ? "1px solid #{COLOR_MONEY}" : '1px solid #ced4da',
                          borderRadius: '4px',
              cursor: can_afford ? 'pointer' : 'not-allowed',
              opacity: can_afford ? '1' : '0.6',
              whiteSpace: 'nowrap',
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              boxShadow: can_afford ? '0 1px 2px rgba(0,0,0,0.05)' : 'none',
            },
            on: can_afford ? { click: click_handler } : {},
          }, label)
        end

        h(:div, {
          style: {
            display: 'flex',
            flexDirection: 'column',
            gap: '0.35rem',
            width: '100%',
            alignItems: 'flex-start',
          },
        }, [
render_action_row('Select Par Price:', [corp_badge, *buttons]),
        ])
      end

      def render_draft_or_auction(step, entity, actions)
        return render_bid(step, entity, actions) unless step

        draft_items = []
        draft_items.concat(step.companies) if step.respond_to?(:companies) && step.companies&.any?
        draft_items.concat(step.minors) if step.respond_to?(:minors) && step.minors&.any?
        draft_items.concat(step.available) if step.respond_to?(:available) && step.available&.any?
        draft_items.concat(step.items) if step.respond_to?(:items) && step.items&.any?

        if @game.respond_to?(:companies) && @game.companies
          acquired_companies = @game.companies.select { |c| c.owner && c.owner.player? && (!c.respond_to?(:closed?) || !c.closed?) }
          draft_items.concat(acquired_companies)
        end
        if @game.respond_to?(:minors) && @game.minors
          acquired_minors = @game.minors.select { |m| m.owner && m.owner.player? && (!m.respond_to?(:closed?) || !m.closed?) }
          draft_items.concat(acquired_minors)
        end

        draft_items = @game.companies.dup if draft_items.empty? && @game.respond_to?(:companies) && @game.companies

        all_game_items = (@game.respond_to?(:companies) ? @game.companies : []) +
                         (@game.respond_to?(:minors) ? @game.minors : [])
        items = draft_items.uniq.sort_by { |item| all_game_items.index(item) || 999 }

        return render_bid(step, entity, actions) if items.empty?

        players = @game.players || []
        active_auction_item = step.respond_to?(:auctioning) ? step.auctioning : nil
        selected_id = Lib::Storage['selected_bid_corp']
        selected_item = active_auction_item || (selected_id ? items.find { |i| i.id.to_s == selected_id.to_s } : nil)

        tbody_rows = items.map do |item|
          is_active = (item == active_auction_item)
          is_selected = (item == selected_item)
          is_owned = item.owner && item.owner.player?

          high_bid_obj = if step.respond_to?(:highest_bid)
                           step.highest_bid(item)
                         elsif step.respond_to?(:high_bid)
                           step.high_bid(item)
                         end
          high_bidder = if step.respond_to?(:high_bidder)
                          step.high_bidder(item)
                        elsif high_bid_obj.respond_to?(:entity)
                          high_bid_obj.entity
                        end
          high_amount = if high_bid_obj.respond_to?(:price)
                          high_bid_obj.price
                        elsif high_bid_obj.is_a?(Numeric)
                          high_bid_obj
                        end

          buy_price = if step.respond_to?(:buy_price)
                        step.buy_price(item)
                      elsif item.respond_to?(:value)
                        item.value
                      else
                        0
                      end

          can_buy = if is_owned || (active_auction_item && !is_active)
                      false
                    elsif step.respond_to?(:may_purchase?)
                      step.may_purchase?(item) && ((entity.respond_to?(:cash) ? entity.cash : 0) >= (item.value || 0))
                    elsif step.respond_to?(:can_buy_company?)
                      step.can_buy_company?(entity, item)
                    elsif step.respond_to?(:can_buy?)
                      begin
                        step.can_buy?(entity, item)
                      rescue ArgumentError
                        step.can_buy?(entity)
                      end
                    elsif actions.include?('buy_company')
                      (entity.respond_to?(:cash) ? entity.cash : 0) >= buy_price
                    else
                      false
                    end

          can_bid = if is_owned || (active_auction_item && !is_active)
                      false
                    elsif can_buy
                      false
                    elsif step.respond_to?(:may_bid?)
                      min_p = step.respond_to?(:min_bid) ? (step.min_bid(item) rescue 0) : 0
                      step.may_bid?(item) && ((entity.respond_to?(:cash) ? entity.cash : 0) >= min_p)
                    elsif step.respond_to?(:can_bid?)
                      begin
                        step.can_bid?(entity, item)
                      rescue ArgumentError
                        step.can_bid?(entity)
                      end
                    elsif actions.include?('bid')
                      min_b = step.respond_to?(:min_bid) ? (step.min_bid(item) rescue step.min_bid) : (item.value || 10)
                      (entity.respond_to?(:cash) ? entity.cash : 0) >= min_b
                    else
                      false
                    end

          can_choose = !is_owned && actions.include?('choose') && (step.respond_to?(:choices_for) ? step.choices_for(item)&.any? : true)

          card_border = if is_active
                          '#ffc107'
                        elsif is_selected
                          '#2563eb'
                        elsif is_owned
                          '#94a3b8'
                        elsif can_buy || can_bid || can_choose
                          '#28a745'
                        else
                          '#cbd5e1'
                        end

          buy_btn = if can_buy
                      h(:button, {
                        style: {
                          padding: '0 5px',
                          height: '1.35rem',
                          fontSize: '0.75rem',
                          fontWeight: 'bold',
                          fontFamily: FONT_MONEY,
                          backgroundColor: '#28a745',
                          color: '#fff',
                          border: 'none',
                          borderRadius: '3px',
                          cursor: 'pointer',
                          whiteSpace: 'nowrap',
                        },
                        on: {
                          click: lambda {
                            if actions.include?('buy_company')
                              process_action(Engine::Action::BuyCompany.new(entity, company: item, price: buy_price))
                            elsif actions.include?('bid')
                              bid_args = { price: buy_price }
                              if item.respond_to?(:company?) && item.company?
                                bid_args[:company] = item
                              elsif item.is_a?(Engine::Minor)
                                bid_args[:minor] = item
                              else
                                bid_args[:corporation] = item
                              end
                              process_action(Engine::Action::Bid.new(entity, **bid_args))
                            end
                          },
                        },
                      }, "Buy #{@game.format_currency(buy_price)}")
                    elsif can_choose
                      h(:button, {
                        style: {
                          padding: '0 5px',
                          height: '1.35rem',
                          fontSize: '0.75rem',
                          fontWeight: 'bold',
                          backgroundColor: '#6f42c1',
                          color: '#fff',
                          border: 'none',
                          borderRadius: '3px',
                          cursor: 'pointer',
                          whiteSpace: 'nowrap',
                        },
                        on: {
                          click: lambda {
                            choice = item.respond_to?(:id) ? item.id : item
                            process_action(Engine::Action::Choose.new(entity, choice: choice))
                          },
                        },
                      }, 'Pick')
                    end

          bid_btn = if can_bid
                      h(:button, {
                        style: {
                          padding: '0 5px',
                          height: '1.35rem',
                          fontSize: '0.75rem',
                          fontWeight: 'bold',
                          backgroundColor: is_selected ? '#1d4ed8' : '#2563eb',
                          color: '#fff',
                          border: 'none',
                          borderRadius: '3px',
                          cursor: 'pointer',
                          whiteSpace: 'nowrap',
                        },
                        on: {
                          click: lambda {
                            Lib::Storage['selected_bid_corp'] = item.id
                            update
                          },
                        },
                      }, is_selected ? 'Bidding' : 'Bid')
                    end

          card_sym = item.respond_to?(:sym) ? item.sym : item.name
          tooltip = item.respond_to?(:company?) && item.company? ? build_company_tooltip(item) : nil
          subtext = (item.respond_to?(:value) && item.value) ? @game.format_currency(item.value) : nil

card_classes = ['game-card']
          card_classes << 'action-buy' if can_buy || can_bid || can_choose || is_active
          card_classes << 'clickable' if can_bid
          card_label = subtext ? "#{card_sym} #{subtext}" : card_sym
          click_handler = can_bid ? -> { Lib::Storage['selected_bid_corp'] = item.id; update } : nil
          item_card_element = render_railcard(card_label, card_classes, click_handler, tooltip)

          row_cells = [
            h(:td, {
              style: {
                padding: '3px 4px 3px 6px',
                textAlign: 'left',
                borderBottom: '1px solid #e2e8f0',
                whiteSpace: 'nowrap',
                width: '1%',
              },
            }, [item_card_element]),
            h(:td, {
              style: {
                padding: '3px 4px',
                textAlign: 'left',
                borderBottom: '1px solid #e2e8f0',
                width: '4.6rem',
                minWidth: '4.6rem',
                whiteSpace: 'nowrap',
              },
            }, [buy_btn].compact),
            h(:td, {
              style: {
                padding: '3px 4px',
                textAlign: 'left',
                borderBottom: '1px solid #e2e8f0',
                width: '3.2rem',
                minWidth: '3.2rem',
                whiteSpace: 'nowrap',
              },
            }, [bid_btn].compact),
          ]

          players.each do |p|
            cell_content = nil
            if is_owned
              if item.owner == p
                cell_content = h(:span, {
                  style: {
                    backgroundColor: '#16a34a',
                    color: '#ffffff',
                    padding: '2px 5px',
                    borderRadius: '3px',
                    fontWeight: 'bold',
                    fontSize: '0.72rem',
                    display: 'inline-block',
                    lineHeight: '1.2',
                  },
                }, 'OWNED')
              else
                cell_content = h(:span, { style: { color: '#cbd5e1' } }, '-')
              end
            else
              p_bid = player_bid_for(step, item, p)
              is_leader = (p == high_bidder && high_amount && high_amount.positive?)

              if is_leader
                cell_content = h(:span, {
                  style: {
                   backgroundColor: '#f3e8ff',
                    color: COLOR_MONEY,
                    border: '1px solid #d8b4fe',
                    padding: '2px 5px',
                    borderRadius: '3px',
                    fontWeight: 'bold',
                    fontSize: '0.75rem',
                    fontFamily: FONT_MONEY,
                    display: 'inline-block',
                    lineHeight: '1.2',
                  },
                }, @game.format_currency(high_amount))
              elsif p_bid && p_bid.positive?
                cell_content = h(:span, {
                  style: {
                    color: '#9ca3af',
                    textDecoration: 'line-through',
                    fontSize: '0.75rem',
                    fontFamily: FONT_MONEY,
                  },
                }, @game.format_currency(p_bid))
              else
                cell_content = h(:span, { style: { color: '#cbd5e1' } }, '-')
              end
            end

            row_cells << h(:td, {
              style: {
                padding: '3px 4px',
                textAlign: 'center',
                borderBottom: '1px solid #e2e8f0',
                backgroundColor: is_selected ? '#f8faff' : 'transparent',
                width: '4.8rem',
                minWidth: '4.2rem',
                maxWidth: '5.5rem',
              },
            }, [cell_content])
          end

          row_bg = if is_active
                     '#fffbeb'
                   elsif is_selected
                     '#eff6ff'
                   else
                     'transparent'
                   end

          h(:tr, { style: { backgroundColor: row_bg } }, row_cells)
        end

        table_element = h(:div, {
          style: {
            width: '100%',
            overflowX: 'auto',
            border: '1px solid #e2e8f0',
            borderRadius: '4px',
            backgroundColor: '#ffffff',
            boxShadow: '0 1px 2px rgba(0,0,0,0.05)',
          },
        }, [
          h(:table, {
            style: {
              width: '100%',
              borderCollapse: 'collapse',
              fontSize: '0.8rem',
              fontFamily: 'inherit',
            },
          }, [
            h(:thead, [
              h(:tr, [
                h(:th, {
                  attrs: { colspan: '3' },
                  style: {
                    padding: '4px 6px',
                    textAlign: 'left',
                    borderBottom: '2px solid #cbd5e1',
                    backgroundColor: '#f8fafc',
                    color: '#475569',
                    fontWeight: 'bold',
                  },
                }, 'Private / Minor'),
                *players.map do |p|
                  is_p_turn = (p == (step.respond_to?(:current_entity) ? step.current_entity : current_entity))
                  h(:th, {
                    style: {
                      padding: '4px 4px',
                      textAlign: 'center',
                      borderBottom: '2px solid #cbd5e1',
                      backgroundColor: is_p_turn ? '#e0f2fe' : '#f8fafc',
                      color: is_p_turn ? '#0369a1' : '#475569',
                      fontWeight: is_p_turn ? 'bold' : '600',
                      width: '4.8rem',
                      minWidth: '4.2rem',
                      maxWidth: '5.5rem',
                    },
                  }, p.name)
                end,
              ]),
            ]),
            h(:tbody, tbody_rows),
            h(:tfoot, [
              h(:tr, [
                h(:td, {
                  attrs: { colspan: '3' },
                  style: {
                    padding: '4px 6px',
                    fontWeight: 'bold',
                    textAlign: 'left',
                    borderTop: '2px solid #cbd5e1',
                    color: '#334155',
                    fontSize: '0.8rem',
                  },
                }, 'Cash:'),
                *players.map do |p|
                  h(:td, {
                    style: {
                      padding: '4px 4px',
                      textAlign: 'center',
                      borderTop: '2px solid #cbd5e1',
                      verticalAlign: 'middle',
                      width: '4.8rem',
                      minWidth: '4.2rem',
                      maxWidth: '5.5rem',
                    },
                  }, [
                    h(:span, {
                      style: {
                        fontWeight: 'bold',
color: COLOR_MONEY,
                        fontSize: '0.85rem',
                        fontFamily: FONT_MONEY,
                      },
                    }, @game.format_currency(p.cash)),
                  ])
                end,
              ]),
            ]),
          ]),
        ])

        bid_detail_row = if selected_item && (actions.include?('bid') || active_auction_item)
                           render_bid(step, entity, actions, selected_item)
                         end

        h(:div, {
          style: {
            display: 'flex',
            flexDirection: 'column',
            gap: '0.35rem',
            width: '100%',
            alignItems: 'flex-start',
          },
        }, [
          table_element,
          bid_detail_row,
        ].compact)
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
                  fontFamily: FONT_MONEY,
                  fontWeight: 'bold',
                  color: COLOR_MONEY,
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
render_railcard(card_text, ['game-card', 'action-buy', 'clickable'], company_click_handler, build_company_tooltip(c), menu_dropdown)
        end.compact

        return nil if company_boxes.empty?

        render_action_row('Buy Privates:', company_boxes)
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
train_boxes << render_railcard(train.name, ['game-card', 'action-sell', 'clickable'], click_handler)
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
              cost_str = "(#{m[1]})"
            elsif (m = btn_text.match(/([+-]?\d+[\w]*)/))
              cost_str = "(#{m[1]})"
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

            cost_str = "(#{@game.format_currency(cost)})" if cost && !cost.zero?
          end

surrender_label = cost_str.empty? ? train.name : "#{train.name} #{cost_str.strip}"
          train_boxes << render_railcard(surrender_label, ['game-card', 'action-sell', 'clickable'], click_handler)
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
train_classes = ['game-card', 'action-buy']
              train_classes << 'clickable' if can_afford
              train_label = "#{variant_str} (Bank: #{@game.format_currency(price)})"
              train_boxes << render_railcard(train_label, train_classes, (can_afford ? click_handler : nil))
                        end
          end
        end

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
                    fontFamily: FONT_MONEY,
                    fontWeight: 'bold',
                    color: COLOR_MONEY,
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

train_boxes << render_railcard("#{t.name} (#{c.id || c.name})", ['game-card', 'action-buy', 'clickable'], train_click_handler, nil, menu_dropdown)
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
        rescue StandardError
          []
        end || []

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

render_railcard("#{pct_str} #{price_str}", ['game-card', 'action-sell', 'clickable'], click_handler)

          end
          rows << render_action_row('Issue:', issue_buttons)
        elsif (@game.round.actions_for(entity) || []).include?('issue_shares')
          rows << render_action_row('Issue:', [
            h(:span, { style: { color: '#888', fontStyle: 'italic', fontSize: '0.85rem' } }, 'No issuable shares available'),
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

render_railcard("#{pct_str} #{price_str}", ['game-card', 'action-buy', 'clickable'], click_handler)

          end
          rows << render_action_row('Redeem:', redeem_buttons)
        end

        return nil if rows.empty?

        h(:div, { style: { display: 'flex', flexDirection: 'column', gap: '0.25rem', width: '100%' } }, rows.compact)
      end

      def render_ground_truth_actions(actions, step)
        return h(:div) if @game.finished

        return h(UpgradeOrDiscardTrains) if actions.include?('discard_train') && actions.include?('swap_train')
if actions.include?('par')
        pending_corp = if step&.respond_to?(:corporation_pending_par) && step.corporation_pending_par
                         step.corporation_pending_par
                       elsif step&.respond_to?(:corporation) && step.corporation
                         step.corporation
                       elsif step&.respond_to?(:par_corporation) && step.par_corporation
                         step.par_corporation
                       elsif step&.respond_to?(:parring) && step.parring
                         step.parring
                       elsif step&.respond_to?(:corporations) && step.corporations&.one?
                         step.corporations.first
                       elsif (step&.current_entity || current_entity)&.corporation?
                         step&.current_entity || current_entity
                       end
        return render_par_step(step, step&.current_entity || current_entity, pending_corp) if pending_corp
      end

        case @game.round
        when Engine::Round::Stock
         is_start_auction_step = (step&.respond_to?(:auctioning) && step.auctioning) ||
                                  (step.class.name =~ /Waterfall|Draft|Auction|Initial/i) ||
                                  (actions.include?('bid') && !actions.include?('buy_shares') && !actions.include?('par'))

          if is_start_auction_step
            render_draft_or_auction(step, step&.current_entity || current_entity, actions)
          else
            Lib::Storage['selected_bid_corp'] = nil if Lib::Storage['selected_bid_corp']
            h(::View::Game::DashboardStock, game: @game)
          end
        when Engine::Round::Operating
          if actions.include?('merge') || actions.include?('convert') || actions.include?('take_loan') || actions.include?('payoff_loan')
            components = []
            components << render_merger_step(step, step&.current_entity || current_entity, actions)
            h(:div, { style: { display: 'flex', flexDirection: 'column', gap: '0.15rem', width: '100%', alignItems: 'flex-start' } }, components.compact)
          elsif actions.include?('buy_shares') && step&.current_entity&.player?
            h(::View::Game::DashboardStock, game: @game)
          elsif actions.include?('bid')
            render_draft_or_auction(step, step&.current_entity || current_entity, actions)
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
              elsif !actions.include?('issue_shares')
                components << render_issue_shares(step, step&.current_entity || current_entity)
              end
              components << h(CorporateBuyShares) if actions.include?('buy_shares') && !actions.include?('run_routes')

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

            h(:div, { style: { display: 'flex', flexDirection: 'column', gap: '0.15rem', width: '100%', alignItems: 'flex-start' } }, components.compact)
          end
        when Engine::Round::Choices
          h(Round::Choices, game: @game)
        when Engine::Round::Auction, Engine::Round::Draft
          render_draft_or_auction(step, step&.current_entity || current_entity, actions)
        when Engine::Round::Merger
          if !(%w[buy_train scrap_train reassign_trains] & actions).empty? && @game.train_actions_always_use_operating_round_view?
            h(Round::Operating, game: @game)
          elsif (%w[merge convert buy_shares corporate_buy_shares take_loan payoff_loan] & actions).any?
            components = []
            components << render_merger_step(step, step&.current_entity || current_entity, actions)
            h(:div, { style: { display: 'flex', flexDirection: 'column', gap: '0.15rem', width: '100%', alignItems: 'flex-start' } }, components.compact)
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