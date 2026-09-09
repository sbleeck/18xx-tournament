# frozen_string_literal: true

# backtick_javascript: true

require 'view/game/actionable'
require 'lib/settings'
require 'lib/storage'
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
        FONT_STD = '"Helvetica Neue", Helvetica, Arial, sans-serif'
        COLOR_INACTIVE = '#e2e8f0'

        needs :game, store: true
        needs :step, default: nil
        needs :entity, default: nil
        needs :corporation, default: nil
        needs :on_cancel, default: nil

        def resolve_step
          @step || @game.round.active_step
        end

        def resolve_actual_corporation(active_step)
          if @corporation && (!active_step.respond_to?(:corporation_pending_par) || !active_step.corporation_pending_par)
            return @corporation
          end

          corp = if active_step.respond_to?(:corporation_pending_par) && active_step.corporation_pending_par
                   active_step.corporation_pending_par
                 elsif active_step.respond_to?(:par_corporation) && active_step.par_corporation
                   active_step.par_corporation
                 elsif active_step.respond_to?(:corporation) && active_step.corporation
                   active_step.corporation
                 end
          return corp if corp

          transacted_company = nil
          %i[company last_company auctioning].each do |m|
            if active_step.respond_to?(m) && (c_val = active_step.send(m))
              transacted_company = c_val if c_val.is_a?(Engine::Company) || c_val.respond_to?(:abilities)
              break if transacted_company
            end
          end

          if !transacted_company && active_step.instance_variable_defined?(:@company)
            c_val = active_step.instance_variable_get(:@company)
            transacted_company = c_val if c_val
          end

          if !transacted_company && @game.respond_to?(:actions) && @game.actions&.any?
            last_act = @game.actions.last
            transacted_company = last_act.company if last_act.respond_to?(:company) && last_act.company
          end

          if transacted_company
            ability = if @game.respond_to?(:abilities)
                        @game.abilities(transacted_company, :shares) || @game.abilities(transacted_company, :close_to_float)
                      end

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

            c_sym = transacted_company.sym.to_s
            c_id = transacted_company.id.to_s
            corp = @game.corporations.find do |c|
              c.id.to_s == c_id || c.name.to_s == c_id || (c.respond_to?(:sym) && c.sym.to_s == c_sym)
            end
            return corp if corp
          end

          @corporation
        end

        def resolve_actor
          if @entity.respond_to?(:player?) && @entity.player?
            @entity
          elsif @entity.respond_to?(:owner) && @entity.owner.respond_to?(:player?) && @entity.owner.player?
            @entity.owner
          elsif @game.round.respond_to?(:current_entity) && @game.round.current_entity&.player?
            @game.round.current_entity
          elsif @game.respond_to?(:current_entity) && @game.current_entity&.player?
            @game.current_entity
          else
            @entity
          end
        end

        def render
          active_step = resolve_step
          actual_corp = resolve_actual_corporation(active_step)
          return h(:div) unless actual_corp

          par_actor = resolve_actor
          return h(:div) unless par_actor

          par_nodes = if active_step.respond_to?(:get_par_prices_with_help)
                        active_step.get_par_prices_with_help(par_actor, actual_corp)
                      elsif active_step.respond_to?(:get_par_prices)
                        active_step.get_par_prices(par_actor, actual_corp)
                      elsif active_step.respond_to?(:par_prices)
                        begin
                          active_step.par_prices(par_actor, actual_corp)
                        rescue ArgumentError
                          active_step.par_prices(actual_corp)
                        end
                      elsif @game.respond_to?(:par_prices)
                        @game.par_prices(actual_corp)
                      else
                        @game.stock_market.par_prices
                      end

          par_nodes = par_nodes.sort_by do |node|
            price = node.is_a?(Array) ? node[0] : node
            price.respond_to?(:price) ? price.price : price
          end

          if @game.respond_to?(:par_chart)
            par_nodes = par_nodes.reject do |node|
              p_obj = node.is_a?(Array) ? node.first : node
              slots = @game.par_chart[p_obj]
              slots && slots.none?(&:nil?)
            end
          end

          corp_badge = render_railcard(actual_corp.name, ['game-card'])
          shares_range = (2..10).to_a

          headers = [
            h(:th, {
                style: {
                  padding: '8px 12px',
                  border: '1px solid #cbd5e1',
                  backgroundColor: COLOR_INACTIVE,
                  color: '#1e293b',
                  fontWeight: 'bold',
                  textAlign: 'center',
                  fontFamily: FONT_STD,
                },
              }, 'Par \ Shares'),
          ]

          shares_range.each do |n|
            headers << h(:th, {
                           style: {
                             padding: '8px 10px',
                             border: '1px solid #cbd5e1',
                             backgroundColor: COLOR_INACTIVE,
                             color: '#1e293b',
                             fontWeight: 'bold',
                             textAlign: 'center',
                             minWidth: '3.2rem',
                             fontFamily: FONT_STD,
                           },
                         }, "#{n}S")
          end

          actor_cash = par_actor.respond_to?(:cash) ? par_actor.cash : 0

          matrix_rows = par_nodes.map do |node|
            price_obj = node.is_a?(Array) ? node[0] : node
            help = node.is_a?(Array) ? node[1] : nil
            price_val = price_obj.respond_to?(:price) ? price_obj.price : price_obj

            float_shares = if @game.respond_to?(:total_shares_to_float)
                             @game.total_shares_to_float(actual_corp, price_val)
                           else
                             (actual_corp.float_percent || 60) / (actual_corp.share_percent || 10)
                           end

            price_label = @game.format_currency(price_val)
            price_label += " (#{help})" if help

            row_cells = [
              h(:th, {
                  style: {
                    padding: '8px 12px',
                    border: '1px solid #cbd5e1',
                    backgroundColor: '#f8fafc',
                    color: '#0f172a',
                    fontWeight: 'bold',
                    fontFamily: FONT_MONEY,
                    textAlign: 'right',
                    whiteSpace: 'nowrap',
                  },
                }, price_label),
            ]

            shares_range.each do |n|
              cost = n * price_val
              can_afford = actor_cash >= cost
              is_float = (n == float_shares)

              bg_color = can_afford ? '#dcfce7' : '#f8fafc'
              fg_color = can_afford ? '#14532d' : '#94a3b8'
              border_style = is_float ? '2px solid #dc2626' : '1px solid #e2e8f0'

              cell_props = {
                style: {
                  padding: '8px 6px',
                  border: border_style,
                  backgroundColor: bg_color,
                  color: fg_color,
                  cursor: can_afford ? 'pointer' : 'not-allowed',
                  textAlign: 'center',
                  fontWeight: is_float ? 'bold' : '600',
                  fontFamily: FONT_MONEY,
                  fontSize: '0.88rem',
                  transition: 'transform 0.08s ease, background-color 0.1s ease',
                },
                on: {},
              }

              if can_afford
                cell_props[:on][:click] = lambda {
                  @on_cancel&.call
                  slot = (@game.par_chart[price_obj].index(nil) if @game.respond_to?(:par_chart) && @game.par_chart[price_obj])
                  args = { corporation: actual_corp, share_price: price_obj }
                  args[:slot] = slot if slot
                  process_action(Engine::Action::Par.new(par_actor, **args))
                }
              end

              row_cells << h(:td, cell_props, @game.format_currency(cost))
            end

            h(:tr, row_cells)
          end

          table_elem = h(:table, {
                           style: {
                             borderCollapse: 'collapse',
                             width: '100%',
                             boxShadow: '0 1px 3px rgba(0,0,0,0.05)',
                           },
                         }, [
            h(:thead, [h(:tr, headers)]),
            h(:tbody, matrix_rows),
          ])

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

          is_minimized = Lib::Storage['par_overlay_minimized'] || false

          saved_left = %x((function() {
            try {
              var l = sessionStorage.getItem('par_overlay_left');
              return (l && l !== 'undefined' && l !== 'null' && !isNaN(parseFloat(l))) ? parseFloat(l) : null;
            } catch(e) { return null; }
          })())
          saved_top = %x((function() {
            try {
              var t = sessionStorage.getItem('par_overlay_top');
              return (t && t !== 'undefined' && t !== 'null' && !isNaN(parseFloat(t))) ? parseFloat(t) : null;
            } catch(e) { return null; }
          })())

          on_header_mousedown = lambda do |event|
            %x(
            var ev = #{event} || (typeof arguments !== 'undefined' ? arguments[0] : null) || window.event;
            if (!ev) return;

            var target = ev.target || ev.srcElement;
            if (target) {
              var tag = (target.tagName || '').toUpperCase();
              if (tag === 'BUTTON' || tag === 'INPUT' || (target.closest && target.closest('button'))) {
                return;
              }
            }

            if (ev.preventDefault) {
              ev.preventDefault();
            }

            var modal = document.getElementById('par-prompt-overlay-dialog');
            if (!modal) return;

            var header = document.getElementById('par-prompt-overlay-header');
            if (header) {
              header.style.cursor = 'grabbing';
            }

            var rect = modal.getBoundingClientRect();
            var shiftX = ev.clientX - rect.left;
            var shiftY = ev.clientY - rect.top;

            modal.style.position = 'fixed';
            modal.style.left = rect.left + 'px';
            modal.style.top = rect.top + 'px';
            modal.style.margin = '0';
            modal.style.transform = 'none';

            function onMouseMove(moveEv) {
              var mEv = moveEv || window.event;
              if (mEv.preventDefault) mEv.preventDefault();

              var newLeft = mEv.clientX - shiftX;
              var newTop = mEv.clientY - shiftY;

              var maxLeft = window.innerWidth - 60;
              var maxTop = window.innerHeight - 40;

              if (newLeft < 10) newLeft = 10;
              if (newLeft > maxLeft) newLeft = maxLeft;
              if (newTop < 0) newTop = 0;
              if (newTop > maxTop) newTop = maxTop;

              modal.style.left = newLeft + 'px';
              modal.style.top = newTop + 'px';
            }

            function onMouseUp(upEv) {
              document.removeEventListener('mousemove', onMouseMove, true);
              document.removeEventListener('mouseup', onMouseUp, true);
              window.removeEventListener('mousemove', onMouseMove, true);
              window.removeEventListener('mouseup', onMouseUp, true);

              if (header) {
                header.style.cursor = 'grab';
              }

              var finalRect = modal.getBoundingClientRect();
              if (finalRect && !isNaN(finalRect.left) && !isNaN(finalRect.top)) {
                try {
                  sessionStorage.setItem('par_overlay_left', finalRect.left);
                  sessionStorage.setItem('par_overlay_top', finalRect.top);
                } catch(err) {}
              }
            }

            document.addEventListener('mousemove', onMouseMove, true);
            document.addEventListener('mouseup', onMouseUp, true);
            window.addEventListener('mousemove', onMouseMove, true);
            window.addEventListener('mouseup', onMouseUp, true);
            )
          end

          reset_pos = lambda do
            %x(
            try {
              sessionStorage.removeItem('par_overlay_left');
              sessionStorage.removeItem('par_overlay_top');
            } catch(e) {}
            var modal = document.getElementById('par-prompt-overlay-dialog');
            if (modal) {
              modal.style.left = '50%';
              modal.style.top = '50%';
              modal.style.transform = 'translate(-50%, -50%)';
              modal.style.margin = '0';
            }
            )
            update
          end

          toggle_minimize = lambda do
            Lib::Storage['par_overlay_minimized'] = !is_minimized
            update
          end

          dialog_style = {
            width: '90%',
            maxWidth: '820px',
            backgroundColor: '#ffffff',
            borderRadius: '8px',
            boxShadow: '0 20px 25px -5px rgba(0, 0, 0, 0.35), 0 0 0 1px rgba(0, 0, 0, 0.1)',
            display: 'flex',
            flexDirection: 'column',
            overflow: 'hidden',
            border: '1px solid #cbd5e1',
            pointerEvents: 'auto',
            position: 'fixed',
            margin: '0',
            zIndex: '100050',
          }

          if saved_left && saved_top
            dialog_style[:left] = "#{saved_left}px"
            dialog_style[:top] = "#{saved_top}px"
            dialog_style[:transform] = 'none'
          else
            dialog_style[:left] = '50%'
            dialog_style[:top] = '50%'
            dialog_style[:transform] = 'translate(-50%, -50%)'
          end

          dialog_style[:maxHeight] = is_minimized ? 'auto' : '88vh'

          header_controls = [
            (if @on_cancel
               h(:button, {
                   attrs: { title: 'Cancel par selection' },
                   style: {
                     padding: '0 10px',
                     height: '1.5rem',
                     fontSize: '0.78rem',
                     fontWeight: 'bold',
                     backgroundColor: '#64748b',
                     color: '#ffffff',
                     border: 'none',
                     borderRadius: '4px',
                     cursor: 'pointer',
                     display: 'inline-flex',
                     alignItems: 'center',
                     justifyContent: 'center',
                   },
                   on: { click: -> { @on_cancel.call } },
                 }, 'Cancel')
             end),
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
                  justify-content: center !important;
                  gap: 0.3rem !important;
                  margin: 0 !important;
                  padding: 0 !important;
                  border: none !important;
                  background: transparent !important;
                  box-shadow: none !important;
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
                  box-shadow: 0 1px 2px rgba(0,0,0,0.05) !important;
                }
              '),
              h(HistoryAndUndo, last_action_id: last_action_id),
            ]),
            h(:button, {
                attrs: { title: is_minimized ? 'Expand overlay' : 'Minimize overlay' },
                style: {
                  padding: '0 8px',
                  height: '1.5rem',
                  fontSize: '0.78rem',
                  fontWeight: '600',
                  backgroundColor: '#f1f5f9',
                  color: '#475569',
                  border: '1px solid #cbd5e1',
                  borderRadius: '4px',
                  cursor: 'pointer',
                  display: 'inline-flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                },
                on: { click: toggle_minimize },
              }, is_minimized ? 'Expand' : 'Minimize'),
          ].compact

          body_content = if is_minimized
                           nil
                         else
                           h(:div, { style: { overflowY: 'auto', padding: '1rem', display: 'flex', flexDirection: 'column', gap: '0.6rem' } }, [
                             h(:div, { style: { fontSize: '0.85rem', color: '#475569' } },
                               "Select par price for #{actual_corp.name}. Red cell border indicates float threshold:"),
                             table_elem,
                           ])
                         end

          dialog_children = [
            h(:div, {
                attrs: { id: 'par-prompt-overlay-header' },
                style: {
                  padding: '0.7rem 1.2rem',
                  borderBottom: is_minimized ? 'none' : '1px solid #e2e8f0',
                  backgroundColor: '#f8fafc',
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center',
                  cursor: 'grab',
                  userSelect: 'none',
                },
                on: {
                  mousedown: on_header_mousedown,
                  dblclick: reset_pos,
                },
              }, [
              h(:div, { style: { display: 'flex', alignItems: 'center', gap: '0.8rem' } }, [
                h(:h2, { style: { margin: '0', fontSize: '1.25rem', color: '#0f172a' } }, 'Establish Par Price'),
                corp_badge,
              ]),
              h(:div, { style: { display: 'flex', alignItems: 'center', gap: '0.4rem' } }, header_controls),
            ]),
          ]
          dialog_children << body_content if body_content

          h(:div, {
              attrs: { id: 'par-prompt-overlay-container' },
              style: {
                position: 'fixed',
                top: '0',
                left: '0',
                right: '0',
                bottom: '0',
                backgroundColor: 'transparent',
                pointerEvents: 'none',
                zIndex: '100050',
              },
            }, [
              h(:div, {
                  attrs: { id: 'par-prompt-overlay-dialog' },
                  style: dialog_style,
                }, dialog_children),
            ])
        end
      end
    end
  end
end
