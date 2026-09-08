# frozen_string_literal: true

# backtick_javascript: true

require 'view/game/actionable'
require 'lib/settings'
require 'view/game/history_and_undo'
require 'view/game/dashboard/railcard_helper'

module View
  module Game
    module Dashboard
      class ParPromptOverlay < Snabberb::Component
        include Actionable
        include Lib::Settings
        include View::Game::Dashboard::RailcardHelper

        FONT_MONEY = '"Courier New", Courier, monospace'

        needs :game, store: true
        needs :step
        needs :entity
        needs :corporation, default: nil

        def resolve_actual_corporation
          return @corporation if @corporation && (!@step.respond_to?(:corporation_pending_par) || !@step.corporation_pending_par)

          # 1. Direct step pointers
          corp = if @step.respond_to?(:corporation_pending_par) && @step.corporation_pending_par
                   @step.corporation_pending_par
                 elsif @step.respond_to?(:par_corporation) && @step.par_corporation
                   @step.par_corporation
                 elsif @step.respond_to?(:corporation) && @step.corporation
                   @step.corporation
                 end
          return corp if corp

          # 2. Check the company in the active step
          transacted_company = nil
          %i[company last_company auctioning].each do |m|
            if @step.respond_to?(m) && (c_val = @step.send(m))
              transacted_company = c_val if c_val.is_a?(Engine::Company) || c_val.respond_to?(:abilities)
              break if transacted_company
            end
          end

          # Check instance variables on the step
          if !transacted_company && @step.instance_variable_defined?(:@company)
            c_val = @step.instance_variable_get(:@company)
            transacted_company = c_val if c_val
          end

          # 3. Check the last executed action in the game history
          if !transacted_company && @game.respond_to?(:actions) && @game.actions&.any?
            last_act = @game.actions.last
            transacted_company = last_act.company if last_act.respond_to?(:company) && last_act.company
          end

          # 4. Resolve corporation from the transacted company's abilities or share associations
          if transacted_company
            # Direct ability query through @game
            ability = if @game.respond_to?(:abilities)
                        @game.abilities(transacted_company, :shares) || @game.abilities(transacted_company, :close_to_float)
                      end

            # Search company's own ability arrays
            if !ability && transacted_company.respond_to?(:all_abilities)
              ability = transacted_company.all_abilities.find { |a| a.type == :shares }
            end
            if !ability && transacted_company.respond_to?(:abilities)
              ability = Array(transacted_company.abilities).find { |a| a.type == :shares }
            end

            if ability&.respond_to?(:shares)
              sh = ability.shares.first
              corp = sh.corporation if sh&.respond_to?(:corporation)
              return corp if corp
            end

            # Check if corporation id or sym matches company id or sym (standard 1830 B&O link)
            c_sym = transacted_company.sym.to_s
            c_id = transacted_company.id.to_s
            corp = @game.corporations.find do |c|
              c.id.to_s == c_id || c.name.to_s == c_id || (c.respond_to?(:sym) && c.sym.to_s == c_sym)
            end
            return corp if corp
          end

          @corporation
        end

        def render
          actual_corp = resolve_actual_corporation
          return h(:div) unless actual_corp

          par_nodes = if @step.respond_to?(:get_par_prices_with_help)
                        @step.get_par_prices_with_help(@entity, actual_corp)
                      elsif @step.respond_to?(:get_par_prices)
                        @step.get_par_prices(@entity, actual_corp)
                      elsif @step.respond_to?(:par_prices)
                        begin
                          @step.par_prices(@entity, actual_corp)
                        rescue ArgumentError
                          @step.par_prices(actual_corp)
                        end
                      elsif @game.respond_to?(:par_prices)
                        @game.par_prices(actual_corp)
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

          corp_badge = render_railcard(actual_corp.name, ['game-card'])

          par_actor = if @entity.respond_to?(:player?) && @entity.player?
                        @entity
                      elsif @entity.respond_to?(:owner) && @entity.owner.respond_to?(:player?) && @entity.owner.player?
                        @entity.owner
                      elsif @game.round.respond_to?(:current_entity) && @game.round.current_entity&.player?
                        @game.round.current_entity
                      else
                        @entity
                      end

          buttons = par_nodes.map do |node|
            price = node.is_a?(Array) ? node[0] : node
            help = node.is_a?(Array) ? node[1] : nil
            price_val = price.respond_to?(:price) ? price.price : price

            price_str = @game.format_currency(price_val)
            label = help ? "#{price_str} (#{help})" : price_str

            multiplier = if actual_corp.respond_to?(:presidents_percent) && actual_corp.respond_to?(:share_percent)
                           (actual_corp.presidents_percent / actual_corp.share_percent).to_i
                         elsif actual_corp.respond_to?(:shares) && actual_corp.shares.first&.president
                           actual_corp.shares.first.num_shares || 2
                         else
                           2
                         end
            cost = price_val * multiplier
            cash = par_actor.respond_to?(:cash) ? par_actor.cash : 0
            can_afford = cash >= cost

            click_handler = lambda {
              slot = (@game.par_chart[price].index(nil) if @game.respond_to?(:par_chart) && @game.par_chart[price])
              args = { corporation: actual_corp, share_price: price }
              args[:slot] = slot if slot
              process_action(Engine::Action::Par.new(par_actor, **args))
            }

            h(:button, {
                attrs: { disabled: !can_afford },
                style: {
                  height: '2.4rem',
                  padding: '0 16px',
                  fontSize: '1rem',
                  fontWeight: 'bold',
                  fontFamily: FONT_MONEY,
                  backgroundColor: can_afford ? '#f0fdf4' : '#f1f5f9',
                  color: can_afford ? '#15803d' : '#94a3b8',
                  border: can_afford ? '2px solid #16a34a' : '1px solid #cbd5e1',
                  borderRadius: '6px',
                  cursor: can_afford ? 'pointer' : 'not-allowed',
                  opacity: can_afford ? '1' : '0.6',
                  whiteSpace: 'nowrap',
                  display: 'inline-flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  boxShadow: can_afford ? '0 2px 4px rgba(22, 163, 74, 0.25)' : 'none',
                },
                on: can_afford ? { click: click_handler } : {},
              }, label)
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

          h(:div, {
              attrs: { id: 'par-prompt-overlay-container' },
              style: {
                position: 'fixed',
                top: '0',
                left: '0',
                right: '0',
                bottom: '0',
                backgroundColor: 'rgba(15, 23, 42, 0.75)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                zIndex: '100050',
                pointerEvents: 'auto',
              },
            }, [
            h(:div, {
                attrs: { id: 'par-prompt-modal-card' },
                style: {
                  width: '90%',
                  maxWidth: '560px',
                  backgroundColor: '#ffffff',
                  borderRadius: '10px',
                  boxShadow: '0 25px 50px -12px rgba(0, 0, 0, 0.55)',
                  border: '2px solid #16a34a',
                  display: 'flex',
                  flexDirection: 'column',
                  overflow: 'hidden',
                },
              }, [
              h(:div, {
                  style: {
                    padding: '0.8rem 1.2rem',
                    backgroundColor: '#f0fdf4',
                    borderBottom: '1px solid #bbf7d0',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                  },
                }, [
                h(:div, { style: { display: 'flex', alignItems: 'center', gap: '0.6rem' } }, [
                  h(:span, { style: { fontSize: '1.05rem', fontWeight: 'bold', color: '#166534' } }, 'Set Par Price Required'),
                  corp_badge,
                ]),
                h(:div, { style: { display: 'flex', alignItems: 'center', gap: '0.8rem' } }, [
                  h(:span, { style: { fontSize: '0.85rem', fontWeight: '600', color: '#15803d' } }, par_actor.name),
                  h(:div, { attrs: { class: 'par-prompt-undo-wrapper' } }, [
                    h(:style, {}, '
                      .par-prompt-undo-wrapper #history,
                      .par-prompt-undo-wrapper .history,
                      .par-prompt-undo-wrapper input,
                      .par-prompt-undo-wrapper button:not(#undo):not(#redo) {
                        display: none !important;
                      }
                      .par-prompt-undo-wrapper,
                      .par-prompt-undo-wrapper * {
                        box-sizing: border-box !important;
                      }
                      .par-prompt-undo-wrapper,
                      .par-prompt-undo-wrapper div,
                      .par-prompt-undo-wrapper #history_and_undo,
                      .par-prompt-undo-wrapper .history_and_undo {
                        display: inline-flex !important;
                        flex-direction: row !important;
                        flex-wrap: nowrap !important;
                        align-items: center !important;
                        gap: 0.3rem !important;
                        margin: 0 !important;
                        padding: 0 !important;
                        border: none !important;
                        background: transparent !important;
                      }
                      .par-prompt-undo-wrapper button#undo,
                      .par-prompt-undo-wrapper button#redo {
                        display: inline-flex !important;
                        height: 1.5rem !important;
                        min-height: 1.5rem !important;
                        max-height: 1.5rem !important;
                        padding: 0 8px !important;
                        font-size: 0.78rem !important;
                        font-weight: 600 !important;
                        background-color: #f1f5f9 !important;
                        color: #475569 !important;
                        border: 1px solid #cbd5e1 !important;
                        border-radius: 4px !important;
                        cursor: pointer !important;
                        margin: 0 !important;
                        line-height: 1 !important;
                      }
                      .par-prompt-undo-wrapper button#undo:hover:not(:disabled),
                      .par-prompt-undo-wrapper button#redo:hover:not(:disabled) {
                        background-color: #e2e8f0 !important;
                        color: #1e293b !important;
                        border-color: #94a3b8 !important;
                      }
                      .par-prompt-undo-wrapper button#undo:disabled,
                      .par-prompt-undo-wrapper button#redo:disabled {
                        background-color: #f8fafc !important;
                        color: #cbd5e1 !important;
                        border-color: #e2e8f0 !important;
                        cursor: not-allowed !important;
                        opacity: 0.6 !important;
                      }
                    '),
                    h(HistoryAndUndo, last_action_id: last_action_id),
                  ]),
                ]),
              ]),
              h(:div, {
                  style: {
                    padding: '1.4rem',
                    display: 'flex',
                    flexDirection: 'column',
                    gap: '1.2rem',
                    alignItems: 'center',
                  },
                }, [
                h(:div, { style: { fontSize: '0.92rem', color: '#334155', textAlign: 'center' } },
                  "Purchasing this card requires establishing the par value for #{actual_corp.name} to continue:"),
                h(:div, {
                    style: {
                      display: 'flex',
                      flexWrap: 'wrap',
                      gap: '0.6rem',
                      justifyContent: 'center',
                      width: '100%',
                    },
                  }, buttons),
              ]),
            ]),
          ])
        end
      end
    end
  end
end
