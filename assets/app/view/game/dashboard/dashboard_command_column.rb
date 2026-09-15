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
require 'view/game/round/operating'

class String
  def player?
    false
  end
end

module Engine
  class Minor
    def player?
      false
    end
  end

  class Hex
    def to_s
      if respond_to?(:name) && name
        name.to_s
      else
        (respond_to?(:id) && id ? id.to_s : super)
      end
    end
  end
end

module View
  module Game
    module Dashboard
      class ManualRouteOverlay < Snabberb::Component
        include Actionable
        include Lib::Settings
        include View::Game::Dashboard::RailcardHelper

        FONT_MONEY = '"Courier New", Courier, monospace'
        COLOR_MONEY = '#4c1d95'
        SCREAMING_PALETTE = ['#ff1493', '#00ffff', '#7fff00', '#ff00ff'].freeze

        needs :game, store: true
        needs :routes, store: true, default: []
        needs :selected_route, store: true, default: nil
        needs :cmd_router_running, store: true, default: false
        needs :show_manual_routes, store: true, default: false
        needs :entity, default: nil

        def current_entity
          @entity ||
            @game.round.active_step&.current_entity ||
            (@game.round.respond_to?(:current_entity) ? @game.round.current_entity : nil) ||
            @game.current_entity
        rescue NotImplementedError, StandardError
          nil
        end

        def active_routes
          @routes.select { |r| r.chains.any? }
        end

        def render
          entity = current_entity
          return h(:div) unless entity

          trains = begin
            if @game.respond_to?(:route_trains)
              @game.route_trains(entity)
            elsif entity.respond_to?(:trains)
              entity.trains
            else
              []
            end
          rescue StandardError
            entity.respond_to?(:trains) ? entity.trains : []
          end || []

          trains = entity.trains || [] if trains.empty? && entity.respond_to?(:trains)

          if @routes.empty? && trains.any?
            trains.each do |t|
              @routes << Engine::Route.new(@game, @game.phase, t, routes: @routes)
            end
            store(:routes, @routes, skip: true)
          end

          current_route = @selected_route || @routes.first
          if current_route != @selected_route && current_route
            @selected_route = current_route
            store(:selected_route, @selected_route, skip: true)
          end

          logo_src = begin
            setting_for(:simple_logos, @game) ? entity&.simple_logo : entity&.logo
          rescue StandardError
            nil
          end

          bg_color = entity.respond_to?(:color) ? (entity.color || '#4169e1') : '#333333'
          text_color = entity.respond_to?(:text_color) ? (entity.text_color || 'white') : 'white'

          logo_element = if logo_src
                           h(:img, {
                               attrs: { src: logo_src, alt: entity&.name || 'Logo' },
                               style: {
                                 width: '85px',
                                 height: '85px',
                                 objectFit: 'contain',
                                 flexShrink: '0',
                               },
                             })
                         else
                           h(:div, {
                               style: {
                                 width: '85px',
                                 height: '85px',
                                 fontSize: '1.8rem',
                                 fontWeight: 'bold',
                                 display: 'flex',
                                 alignItems: 'center',
                                 justifyContent: 'center',
                                 backgroundColor: bg_color,
                                 color: text_color,
                                 borderRadius: '8px',
                                 flexShrink: '0',
                               },
                             }, entity&.id || entity&.name || 'N/A')
                         end

          train_cards = trains.map.with_index do |train, idx|
            route = @routes.find { |r| r.train == train }
            selected = @selected_route&.train == train
            track_color = SCREAMING_PALETTE[idx % SCREAMING_PALETTE.size]

            rev_val = begin
              if route && route.chains.any?
                @game.respond_to?(:format_revenue_currency) ? @game.format_revenue_currency(route.revenue) : @game.format_currency(route.revenue)
              else
                @game.format_currency(0)
              end
            rescue StandardError
              'Err'
            end

            stops_str = begin
              if route && route.chains.any?
                dist = if route.respond_to?(:distance_str)
                         route.distance_str
                       else
                         (route.respond_to?(:distance) ? route.distance : nil)
                       end
                dist ? "#{dist} stops" : 'Routed'
              else
                'not assigned'
              end
            rescue StandardError
              'not assigned'
            end

            card_click = lambda {
              target_route = @routes.find { |r| r.train == train }
              unless target_route
                target_route = Engine::Route.new(@game, @game.phase, train, routes: @routes)
                @routes << target_route
                store(:routes, @routes)
              end
              store(:selected_route, target_route)
              update
            }

            card_classes = %w[game-card action-buy card-train]
            card_classes << 'clickable' if selected
            train_badge = render_railcard(train.name, card_classes, card_click)

            h(:div, {
                style: {
                  display: 'flex',
                  flexDirection: 'column',
                  alignItems: 'center',
                  justifyContent: 'center',
                  padding: '0.4rem 0.6rem',
                  minWidth: '6.2rem',
                  backgroundColor: selected ? '#ffffff' : '#f8fafc',
                  border: "2px solid #{selected ? track_color : '#cbd5e1'}",
                  borderRadius: '6px',
                  cursor: 'pointer',
                  boxShadow: selected ? "0 0 8px #{track_color}88" : '0 1px 2px rgba(0,0,0,0.05)',
                  opacity: selected ? '1.0' : '0.75',
                },
                on: { click: card_click },
              }, [
              h(:div, { style: { display: 'flex', alignItems: 'center', gap: '0.4rem' } }, [
                h(:span, {
                    style: {
                      width: '0.75rem',
                      height: '0.75rem',
                      borderRadius: '50%',
                      backgroundColor: track_color,
                      display: 'inline-block',
                      flexShrink: '0',
                    },
                  }),
                train_badge,
              ]),
              h(:span, { style: { fontSize: '0.75rem', color: '#64748b', marginTop: '0.2rem' } }, stops_str),
              h(:span, {
                  style: {
                    fontWeight: 'bold',
                    fontSize: '0.95rem',
                    fontFamily: FONT_MONEY,
                    color: COLOR_MONEY,
                    marginTop: '0.15rem',
                  },
                }, rev_val),
            ])
          end

          curr_idx = @routes.index(@selected_route) || 0
          active_color = SCREAMING_PALETTE[curr_idx % SCREAMING_PALETTE.size]
          err_msg = nil
          begin
            @selected_route&.revenue if @selected_route&.chains&.any?
          rescue Engine::GameError, StandardError => e
            err_msg = e.to_s
          end

          clear_selected = lambda {
            @selected_route&.reset!
            store(:selected_route, @selected_route)
            store(:routes, @routes)
            update
          }

          clear_all_routes = lambda {
            @routes.each(&:reset!)
            @game.reset_adjustable_trains!(entity, @routes) if @game.respond_to?(:reset_adjustable_trains!)
            store(:routes, @routes)
            store(:selected_route, @routes.first)
            update
          }

          trigger_auto = lambda {
            store(:cmd_router_running, true)
            update
            lambda {
              `setTimeout(function() {`
              begin
                flash_cb = lambda do |msg|
                  store(:flash_opts, { message: msg }, skip: false)
                end
                router = Engine::AutoRouter.new(@game, flash_cb)
                router_entity = @game.current_entity || entity
                p_timeout = setting_for(:path_timeout).to_i
                p_timeout = 10_000 if p_timeout.zero?
                r_timeout = setting_for(:route_timeout).to_i
                r_timeout = 10_000 if r_timeout.zero?

                @routes.each(&:reset!) if @routes&.any?
                @game.reset_adjustable_trains!(entity, @routes) if @game.respond_to?(:reset_adjustable_trains!)

                router.compute(
                  router_entity,
                  routes: [],
                  path_timeout: p_timeout,
                  route_timeout: r_timeout,
                  callback: lambda do |computed_routes|
                    routes_list = computed_routes || []
                    store(:routes, routes_list, skip: true)
                    store(:selected_route, routes_list.first, skip: true)

                    auto_rev = 0
                    routes_list.each do |r|
                      auto_rev += r.revenue if r.chains.any?
                    rescue Engine::GameError, StandardError
                    end

                    storage_key = "rev_override_#{entity&.id}"
                    last_base_key = "last_base_rev_#{entity&.id}"
                    Lib::Storage[storage_key] = auto_rev
                    Lib::Storage[last_base_key] = auto_rev

                    store(:cmd_router_running, false)
                    update
                  end
                )
              rescue Exception
                store(:cmd_router_running, false)
                update
              end
              `}, 50);`
            }.call
          }

          base_revenue = 0
          active_routes.each do |r|
            base_revenue += r.revenue if r.chains.any?
          rescue Engine::GameError, StandardError
          end
          storage_key = "rev_override_#{entity&.id}"
          current_revenue = Lib::Storage[storage_key] ? Lib::Storage[storage_key].to_i : base_revenue
          formatted_rev = @game.respond_to?(:format_revenue_currency) ? @game.format_revenue_currency(current_revenue) : @game.format_currency(current_revenue)

          submit_and_close = lambda {
            routes_to_submit = active_routes
            process_action(Engine::Action::RunRoutes.new(
              entity,
              routes: routes_to_submit,
              extra_revenue: @game.extra_revenue(entity, routes_to_submit) + (current_revenue - base_revenue)
            ))
            store(:selected_route, nil, skip: true)
            store(:show_manual_routes, false)
            Lib::Storage['cmd_manual_routes'] = false
            update
          }

          close_manual = lambda {
            store(:selected_route, nil, skip: true)
            store(:show_manual_routes, false)
            Lib::Storage['cmd_manual_routes'] = false
            update
          }

          is_minimized = Lib::Storage['manual_route_overlay_minimized'] || false

          saved_left = %x((function() {
            try {
              var l = sessionStorage.getItem('manual_route_overlay_left');
              var parsed = parseFloat(l);
              if (l && l !== 'undefined' && l !== 'null' && !isNaN(parsed) && parsed >= 10 && parsed < (window.innerWidth - 100)) {
                return parsed;
              }
              return null;
            } catch(e) { return null; }
          })())
          saved_top = %x((function() {
            try {
              var t = sessionStorage.getItem('manual_route_overlay_top');
              var parsed = parseFloat(t);
              if (t && t !== 'undefined' && t !== 'null' && !isNaN(parsed) && parsed >= 10 && parsed < (window.innerHeight - 80)) {
                return parsed;
              }
              return null;
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

            if (ev.preventDefault) ev.preventDefault();

            var modal = document.getElementById('manual-route-overlay-dialog');
            if (!modal) return;

            var header = document.getElementById('manual-route-overlay-header');
            if (header) header.style.cursor = 'grabbing';

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

              var maxLeft = window.innerWidth - 80;
              var maxTop = window.innerHeight - 50;

              if (newLeft < 10) newLeft = 10;
              if (newLeft > maxLeft) newLeft = maxLeft;
              if (newTop < 0) newTop = 0;
              if (newTop > maxTop) newTop = maxTop;

              modal.style.left = newLeft + 'px';
              modal.style.top = newTop + 'px';
            }

            function onMouseUp() {
              document.removeEventListener('mousemove', onMouseMove, true);
              document.removeEventListener('mouseup', onMouseUp, true);
              window.removeEventListener('mousemove', onMouseMove, true);
              window.removeEventListener('mouseup', onMouseUp, true);

              if (header) header.style.cursor = 'grab';

              var finalRect = modal.getBoundingClientRect();
              if (finalRect && !isNaN(finalRect.left) && !isNaN(finalRect.top)) {
                try {
                  sessionStorage.setItem('manual_route_overlay_left', finalRect.left);
                  sessionStorage.setItem('manual_route_overlay_top', finalRect.top);
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
              sessionStorage.removeItem('manual_route_overlay_left');
              sessionStorage.removeItem('manual_route_overlay_top');
            } catch(e) {}
            var modal = document.getElementById('manual-route-overlay-dialog');
            if (modal) {
              modal.style.left = '50%';
              modal.style.top = '45%';
              modal.style.transform = 'translate(-50%, -50%)';
              modal.style.margin = '0';
            }
            )
            update
          end

          toggle_minimize = lambda do
            Lib::Storage['manual_route_overlay_minimized'] = !is_minimized
            update
          end

          dialog_style = {
            width: '650px',
            maxWidth: '94vw',
            backgroundColor: '#ffffff',
            borderRadius: '8px',
            boxShadow: '0 20px 25px -5px rgba(0, 0, 0, 0.4), 0 0 0 1px rgba(0, 0, 0, 0.15)',
            display: 'flex',
            flexDirection: 'column',
            overflow: 'hidden',
            border: '2px solid #0f172a',
            pointerEvents: 'auto',
            margin: '0',
            zIndex: '100060',
          }
          if saved_left && saved_top
            dialog_style[:position] = 'fixed'
            dialog_style[:left] = "#{saved_left}px"
            dialog_style[:top] = "#{saved_top}px"
            dialog_style[:transform] = 'none'
          else
            dialog_style[:position] = 'relative'
          end

          header_controls = [
            h(:button, {
                attrs: { title: is_minimized ? 'Expand overlay' : 'Minimize overlay' },
                style: {
                  padding: '0 8px',
                  height: '1.5rem',
                  fontSize: '0.78rem',
                  fontWeight: '600',
                  backgroundColor: '#334155',
                  color: '#ffffff',
                  border: '1px solid #475569',
                  borderRadius: '4px',
                  cursor: 'pointer',
                  display: 'inline-flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                },
                on: { click: toggle_minimize },
              }, is_minimized ? 'Expand' : 'Minimize'),
            h(:button, {
                attrs: { title: 'Close manual routing' },
                style: {
                  background: 'transparent',
                  border: 'none',
                  color: '#cbd5e1',
                  fontSize: '1.2rem',
                  fontWeight: 'bold',
                  cursor: 'pointer',
                  padding: '0 6px',
                  lineHeight: '1',
                },
                on: { click: close_manual },
              }, '✕'),
          ]

          body_content = if is_minimized
                           nil
                         else
                           h(:div, {
                               style: {
                                 padding: '0.9rem',
                                 display: 'flex',
                                 flexDirection: 'row',
                                 alignItems: 'center',
                                 gap: '1rem',
                               },
                             }, [
                             logo_element,
                             h(:div, {
                                 style: {
                                   display: 'flex',
                                   flexDirection: 'column',
                                   gap: '0.7rem',
                                   flex: '1 1 auto',
                                   minWidth: '0',
                                 },
                               }, [
                               (if train_cards.any?
                                  h(:div, { style: { display: 'flex', flexDirection: 'row', gap: '0.5rem', alignItems: 'center', overflowX: 'auto', paddingBottom: '0.2rem' } }, train_cards)
                                else
                                  h(:div, { style: { color: '#64748b', fontStyle: 'italic', fontSize: '0.85rem' } }, "No trains available for #{entity.name}")
                                end),
                               h(:div, { style: { fontSize: '0.82rem', minHeight: '1.3rem', display: 'flex', alignItems: 'center' } }, [
                                 if err_msg
                                   h(:span, { style: { color: '#dc2626', fontWeight: 'bold' } }, "⚠️ #{err_msg}")
                                 else
                                   track_info = begin
                                     if @selected_route&.chains&.any? && @selected_route.respond_to?(:stops)
                                       stops = @selected_route.stops.map do |stop|
                                         rev = begin
                                           if @selected_route.respond_to?(:stop_revenue)
                                             @selected_route.stop_revenue(stop)
                                           elsif stop.respond_to?(:route_revenue)
                                             stop.route_revenue(@game.phase, @selected_route.train)
                                           elsif stop.respond_to?(:revenue)
                                             stop.revenue(@selected_route.train, @game.phase)
                                           end
                                         rescue StandardError
                                           nil
                                         end
                                         hex_name = stop.respond_to?(:hex) && stop.hex ? stop.hex.name : stop.to_s
                                         rev ? "#{hex_name} (#{@game.format_currency(rev)})" : hex_name
                                       end.join(' ➔ ')
                                       stops.empty? ? 'No stops connected' : "Track: #{stops}"
                                     else
                                       'Click revenue centers on the map to route or cycle paths.'
                                     end
                                   rescue StandardError
                                     'Click revenue centers on the map to route or cycle paths.'
                                   end

                                   h(:span, { style: { color: '#334155' } }, [
                                     h(:strong, { style: { color: active_color } }, "Train #{@selected_route&.train&.name || '-'}: "),
                                     h(:span, track_info),
                                   ])
                                 end,
                               ]),
                               h(:div, { style: { display: 'flex', flexDirection: 'row', gap: '0.5rem', alignItems: 'center', marginTop: '0.2rem' } }, [
                                 h(:button, {
                                     style: { height: '1.85rem', padding: '0 10px', fontSize: '0.82rem', fontWeight: 'bold', backgroundColor: '#f1f5f9', border: '1px solid #cbd5e1', borderRadius: '4px', cursor: 'pointer' },
                                     on: { click: clear_selected },
                                   }, 'Clear Train'),
                                 h(:button, {
                                     style: { height: '1.85rem', padding: '0 10px', fontSize: '0.82rem', fontWeight: 'bold', backgroundColor: '#f1f5f9', border: '1px solid #cbd5e1', borderRadius: '4px', cursor: 'pointer' },
                                     on: { click: clear_all_routes },
                                   }, 'Clear All'),
                                 h(:button, {
                                     style: { height: '1.85rem', padding: '0 12px', fontSize: '0.82rem', fontWeight: 'bold', backgroundColor: '#2563eb', color: '#fff', border: 'none', borderRadius: '4px', cursor: 'pointer' },
                                     on: { click: trigger_auto },
                                   }, 'Auto'),
                                 h(:div, { style: { display: 'flex', alignItems: 'center', gap: '0.25rem', marginLeft: 'auto' } }, [
                                   h(:button, {
                                       attrs: { title: 'Decrease revenue override by 10' },
                                       style: {
                                         width: '1.85rem',
                                         height: '1.85rem',
                                         fontSize: '1rem',
                                         fontWeight: 'bold',
                                         cursor: 'pointer',
                                         backgroundColor: '#f1f5f9',
                                         border: '1px solid #cbd5e1',
                                         borderRadius: '4px',
                                         display: 'inline-flex',
                                         alignItems: 'center',
                                         justifyContent: 'center',
                                         padding: '0',
                                         lineHeight: '1',
                                       },
                                       on: {
                                         click: lambda {
                                           Lib::Storage[storage_key] = [current_revenue - 10, 0].max
                                           update
                                         },
                                       },
                                     }, '-'),
                                   h(:button, {
                                       attrs: { title: 'Increase revenue override by 10' },
                                       style: {
                                         width: '1.85rem',
                                         height: '1.85rem',
                                         fontSize: '1rem',
                                         fontWeight: 'bold',
                                         cursor: 'pointer',
                                         backgroundColor: '#f1f5f9',
                                         border: '1px solid #cbd5e1',
                                         borderRadius: '4px',
                                         display: 'inline-flex',
                                         alignItems: 'center',
                                         justifyContent: 'center',
                                         padding: '0',
                                         lineHeight: '1',
                                       },
                                       on: {
                                         click: lambda {
                                           Lib::Storage[storage_key] = current_revenue + 10
                                           update
                                         },
                                       },
                                     }, '+'),
                                   h(:button, {
                                       style: {
                                         height: '1.85rem',
                                         padding: '0 14px',
                                         fontSize: '0.9rem',
                                         fontWeight: 'bold',
                                         backgroundColor: '#16a34a',
                                         color: '#fff',
                                         border: 'none',
                                         borderRadius: '4px',
                                         cursor: 'pointer',
                                         boxShadow: '0 1px 3px rgba(0,0,0,0.15)',
                                       },
                                       on: { click: submit_and_close },
                                     }, "Submit #{formatted_rev}"),
                                 ]),
                               ]),
                             ]),
                           ])
                         end

          dialog_children = [
            h(:div, {
                attrs: { id: 'manual-route-overlay-header' },
                style: {
                  padding: '0.7rem 1.1rem',
                  backgroundColor: '#0f172a',
                  color: '#ffffff',
                  borderBottom: is_minimized ? 'none' : '1px solid #e2e8f0',
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
              h(:div, [
                h(:div, { style: { display: 'flex', alignItems: 'center', gap: '0.5rem' } }, [
                  h(:span, { style: { fontWeight: 'bold', fontSize: '1rem' } }, "Manual Route Selection — #{entity.name}"),
                  h(:span, { style: { fontSize: '0.75rem', color: '#94a3b8', fontStyle: 'italic' } }, '(drag to move, dbl-click center)'),
                ]),
              ]),
              h(:div, { style: { display: 'flex', alignItems: 'center', gap: '0.4rem' } }, header_controls),
            ]),
          ]
          dialog_children << body_content if body_content

          h(:div, {
              attrs: { id: 'manual-route-overlay-container' },
              style: {
                position: 'fixed',
                top: '0',
                left: '0',
                right: '0',
                bottom: '0',
                backgroundColor: 'transparent',
                pointerEvents: 'none',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                zIndex: '1000000',
              },
            }, [
            h(:div, { attrs: { id: 'manual-route-overlay-dialog' }, style: dialog_style }, dialog_children),
          ])
        end
      end

      class DraftOverlay < Snabberb::Component
        include Actionable
        include Lib::Settings
        include View::Game::Dashboard::RailcardHelper

        FONT_MONEY = '"Courier New", Courier, monospace'
        COLOR_MONEY = '#4c1d95'

        needs :game, store: true

        def current_entity
          @game.round.active_step&.current_entity ||
            (@game.round.respond_to?(:current_entity) ? @game.round.current_entity : nil) ||
            @game.current_entity
        rescue NotImplementedError, StandardError
          nil
        end

        def render
          step = @game.round.active_step
          entity = current_entity
          return h(:div) unless step && entity

          actions = begin
            @game.round.actions_for(entity)
          rescue StandardError
            step.current_actions || []
          end || []

          raw_hand = []
          raw_hand.concat(step.companies) if step.respond_to?(:companies) && step.companies&.any?
          raw_hand.concat(step.minors) if step.respond_to?(:minors) && step.minors&.any?
          raw_hand.concat(step.available) if step.respond_to?(:available) && step.available&.any?
          raw_hand.concat(step.items) if step.respond_to?(:items) && step.items&.any?
          raw_hand.concat(step.cards) if step.respond_to?(:cards) && step.cards&.any?

          available_choices = if step.respond_to?(:choices_for)
                                begin
                                  step.choices_for(entity)
                                rescue ArgumentError
                                  step.choices_for
                                rescue StandardError
                                  nil
                                end
                              elsif step.respond_to?(:choices)
                                begin
                                  step.choices(entity)
                                rescue ArgumentError
                                  step.choices
                                rescue StandardError
                                  nil
                                end
                              end

          choice_list = if available_choices.is_a?(Hash)
                          available_choices.keys
                        elsif available_choices.is_a?(Array)
                          available_choices
                        else
                          []
                        end
          raw_hand.concat(choice_list) if choice_list.any?

          has_blank_card = raw_hand.any? do |c|
            c.is_a?(Engine::Player) || (c.respond_to?(:player?) && c.player?) || c.to_s =~ /Player/i
          end

          find_entity = lambda do |token|
            return token if token.is_a?(Engine::Company) || token.is_a?(Engine::Minor)

            if token.is_a?(String) || token.is_a?(Symbol)
              (@game.respond_to?(:companies) ? @game.companies.find { |c| c.id.to_s == token.to_s || (c.respond_to?(:sym) && c.sym.to_s == token.to_s) } : nil) ||
              (@game.respond_to?(:minors) ? @game.minors.find { |m| m.id.to_s == token.to_s || m.name.to_s == token.to_s } : nil)
            end
          end

          draft_items = []
          raw_hand.each do |c|
            ent = find_entity.call(c)
            draft_items << ent if ent
          end

          if @game.respond_to?(:companies) && @game.companies
            acquired_companies = @game.companies.select do |c|
              c.respond_to?(:owner) && c.owner && c.owner.respond_to?(:player?) && c.owner.player? && (!c.respond_to?(:closed?) || !c.closed?)
            end
            draft_items.concat(acquired_companies)
          end

          if @game.respond_to?(:minors) && @game.minors
            acquired_minors = @game.minors.select do |m|
              m.respond_to?(:owner) && m.owner && m.owner.respond_to?(:player?) && m.owner.player? && (!m.respond_to?(:closed?) || !m.closed?)
            end
            draft_items.concat(acquired_minors)
          end

          if draft_items.empty?
            draft_items = (@game.respond_to?(:companies) ? (@game.companies || []).dup : []) +
                          (@game.respond_to?(:minors) ? (@game.minors || []).dup : [])
          end

          all_game_items = (@game.respond_to?(:companies) ? @game.companies : []) +
                           (@game.respond_to?(:minors) ? @game.minors : [])
          items = draft_items.compact.uniq.sort_by { |item| all_game_items.index(item) || 999 }

          players = @game.players || []

          rows = items.map do |item|
            is_owned = item.respond_to?(:owner) && item.owner && item.owner.respond_to?(:player?) && item.owner.player?

            item_price = if step.respond_to?(:min_bid)
                           begin
                             step.min_bid(item)
                           rescue ArgumentError
                             step.min_bid
                           rescue StandardError
                             (item.respond_to?(:value) ? item.value : 0)
                           end
                         elsif step.respond_to?(:buy_price)
                           step.buy_price(item)
                         elsif item.respond_to?(:value)
                           item.value
                         else
                           0
                         end

            is_in_hand = raw_hand.empty? || raw_hand.any? do |c|
              c == item ||
                (item.respond_to?(:id) && (c == item.id || c == item.id.to_s)) ||
                (item.respond_to?(:name) && c == item.name) ||
                (item.respond_to?(:sym) && c == item.sym)
            end

            can_afford = (entity.respond_to?(:cash) ? entity.cash : 0) >= item_price

            exec_choose = lambda {
              if actions.include?('bid')
                bid_args = { price: item_price }
                if item.respond_to?(:company?) && item.company?
                  bid_args[:company] = item
                elsif item.is_a?(Engine::Minor)
                  comp = @game.company_by_id(item.id) if @game.respond_to?(:company_by_id)
                  bid_args[:company] = comp || item
                elsif item.respond_to?(:corporation?) && item.corporation?
                  bid_args[:corporation] = item
                else
                  bid_args[:company] = item
                end
                process_action(Engine::Action::Bid.new(entity, **bid_args))
              elsif actions.include?('buy_company')
                process_action(Engine::Action::BuyCompany.new(entity, company: item, price: item_price))
              elsif actions.include?('choose')
                choice_val = if available_choices.is_a?(Hash)
                               available_choices.keys.find { |k| k == item || (item.respond_to?(:id) && k == item.id) } || item.id
                             else
                               item.respond_to?(:id) ? item.id : item
                             end
                process_action(Engine::Action::Choose.new(entity, choice: choice_val))
              end
            }

            can_choose_item = !is_owned && is_in_hand && can_afford &&
                              (actions.include?('bid') || actions.include?('buy_company') || actions.include?('choose'))

            card_sym = item.respond_to?(:sym) ? item.sym : item.name
            tooltip = build_entity_tooltip(item)
            subtext = item.respond_to?(:value) && item.value ? @game.format_currency(item.value) : nil
            card_classes = ['game-card']
            card_classes << 'action-buy clickable' if can_choose_item
            card_label = subtext ? "#{card_sym} #{subtext}" : card_sym

            item_card = render_railcard(card_label, card_classes, (can_choose_item ? exec_choose : nil), tooltip, entity: item)

            choose_btn = if can_choose_item
                           h(:button, {
                               style: {
                                 padding: '0 10px',
                                 height: '1.6rem',
                                 fontSize: '0.82rem',
                                 fontWeight: 'bold',
                                 fontFamily: FONT_MONEY,
                                 backgroundColor: '#16a34a',
                                 color: '#fff',
                                 border: 'none',
                                 borderRadius: '4px',
                                 cursor: 'pointer',
                               },
                               on: { click: exec_choose },
                             }, "Choose #{@game.format_currency(item_price)}")
                         end

            row_cells = [
              h(:td, { style: { padding: '6px 8px', borderBottom: '1px solid #e2e8f0', width: '1%', whiteSpace: 'nowrap' } }, [item_card]),
              h(:td, { style: { padding: '6px 8px', borderBottom: '1px solid #e2e8f0', width: '8rem', whiteSpace: 'nowrap' } }, [choose_btn].compact),
            ]

            players.each do |p|
              owned_tag = if is_owned && item.respond_to?(:owner) && item.owner == p
                            h(:span, {
                                style: {
                                  backgroundColor: '#16a34a',
                                  color: '#fff',
                                  padding: '3px 6px',
                                  borderRadius: '3px',
                                  fontWeight: 'bold',
                                  fontSize: '0.75rem',
                                },
                              }, 'OWNED')
                          else
                            h(:span, { style: { color: '#cbd5e1' } }, '-')
                          end
              row_cells << h(:td, { style: { padding: '6px 8px', textAlign: 'center', borderBottom: '1px solid #e2e8f0' } }, [owned_tag])
            end

            h(:tr, { style: { backgroundColor: can_choose_item ? '#f0fdf4' : 'transparent' } }, row_cells)
          end

          if has_blank_card || actions.include?('pass')
            blank_pass = -> { process_action(Engine::Action::Pass.new(entity)) }
            blank_badge = render_railcard('Blank Card', %w[game-card action-buy clickable], blank_pass)
            blank_btn = h(:button, {
                            style: {
                              padding: '0 10px',
                              height: '1.6rem',
                              fontSize: '0.82rem',
                              fontWeight: 'bold',
                              backgroundColor: '#64748b',
                              color: '#fff',
                              border: 'none',
                              borderRadius: '4px',
                              cursor: 'pointer',
                            },
                            on: { click: blank_pass },
                          }, 'Take Blank (Pass)')

            blank_cells = [
              h(:td, { style: { padding: '6px 8px', borderBottom: '1px solid #e2e8f0', width: '1%', whiteSpace: 'nowrap' } }, [blank_badge]),
              h(:td, { style: { padding: '6px 8px', borderBottom: '1px solid #e2e8f0', width: '8rem', whiteSpace: 'nowrap' } }, [blank_btn]),
              *players.map { h(:td, { style: { padding: '6px 8px', textAlign: 'center', borderBottom: '1px solid #e2e8f0' } }, [h(:span, { style: { color: '#cbd5e1' } }, '-')]) },
            ]
            rows << h(:tr, { style: { backgroundColor: '#f8fafc' } }, blank_cells)
          end

          h(:div, {
              style: {
                position: 'fixed',
                inset: '0',
                backgroundColor: 'rgba(15, 23, 42, 0.65)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                zIndex: '100000',
                backdropFilter: 'blur(2px)',
              },
            }, [
            h(:div, {
                style: {
                  width: '90%',
                  maxWidth: '920px',
                  maxHeight: '88vh',
                  backgroundColor: '#ffffff',
                  borderRadius: '8px',
                  boxShadow: '0 20px 25px -5px rgba(0, 0, 0, 0.3)',
                  display: 'flex',
                  flexDirection: 'column',
                  overflow: 'hidden',
                  border: '1px solid #cbd5e1',
                },
              }, [
              h(:div, {
                  style: {
                    padding: '0.8rem 1.2rem',
                    borderBottom: '1px solid #e2e8f0',
                    backgroundColor: '#f8fafc',
                    display: 'flex',
                    justifyContent: 'space-between',
                    alignItems: 'center',
                  },
                }, [
                h(:div, [
                  h(:h2, { style: { margin: '0', fontSize: '1.25rem', color: '#0f172a' } }, 'Private Distribution Draft'),
                  h(:span, { style: { fontSize: '0.85rem', color: '#64748b' } }, "Active Player: #{entity.name}"),
                ]),
              ]),
              h(:div, { style: { overflowY: 'auto', padding: '1rem' } }, [
                h(:table, { style: { width: '100%', borderCollapse: 'collapse', fontSize: '0.85rem' } }, [
                  h(:thead, [
                    h(:tr, [
                      h(:th, { attrs: { colspan: '2' }, style: { padding: '6px 8px', textAlign: 'left', borderBottom: '2px solid #cbd5e1', color: '#475569' } }, 'Available Cards'),
                      *players.map do |p|
                        is_current = (p == entity)
                        h(:th, {
                            style: {
                              padding: '6px 8px',
                              textAlign: 'center',
                              borderBottom: '2px solid #cbd5e1',
                              backgroundColor: is_current ? '#e0f2fe' : 'transparent',
                              color: is_current ? '#0369a1' : '#475569',
                              fontWeight: is_current ? 'bold' : '600',
                            },
                          }, p.name)
                      end,
                    ]),
                  ]),
                  h(:tbody, rows),
                  h(:tfoot, [
                    h(:tr, [
                      h(:td, { attrs: { colspan: '2' }, style: { padding: '8px', fontWeight: 'bold', borderTop: '2px solid #cbd5e1', color: '#334155' } }, 'Cash on Hand:'),
                      *players.map do |p|
                        h(:td, {
                            style: {
                              padding: '8px',
                              textAlign: 'center',
                              borderTop: '2px solid #cbd5e1',
                              fontWeight: 'bold',
                              fontFamily: FONT_MONEY,
                              color: COLOR_MONEY,
                            },
                          }, @game.format_currency(p.cash))
                      end,
                    ]),
                  ]),
                ]),
              ]),
            ]),
          ])
        end
      end
    end

    ManualRouteOverlay = Dashboard::ManualRouteOverlay

    class DashboardCommandColumn < Snabberb::Component
      include Actionable
      include Lib::Settings
      include View::Game::Dashboard::RailcardHelper

      FONT_MONEY = '"Courier New", Courier, monospace'
      COLOR_MONEY = '#4c1d95'

      SCREAMING_PALETTE = ['#ff1493', '#00ffff', '#7fff00', '#ff00ff'].freeze
      needs :game, store: true
      needs :game_data, store: true, default: nil
      needs :routes, store: true, default: []
      needs :selected_route, store: true, default: nil
      needs :last_routed_action_id, store: true, default: nil
      needs :last_entity, store: true, default: nil
      needs :cmd_router_running, store: true, default: false
      needs :show_manual_routes, store: true, default: false

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

      def active_player
        entity = current_entity
        return nil unless entity

        if entity.respond_to?(:player?) && entity.player?
          entity
        elsif entity.respond_to?(:player) && entity.player
          entity.player
        elsif entity.respond_to?(:owner) && entity.owner.respond_to?(:player?) && entity.owner.player?
          entity.owner
        end
      end

      def company?(entity)
        return false unless entity

        entity.is_a?(Engine::Company) ||
          (entity.respond_to?(:company?) && entity.company?) ||
          (!entity.respond_to?(:corporation?) && !entity.respond_to?(:minor?) && (entity.respond_to?(:value) || entity.respond_to?(:desc)))
      end

      def home_token_step?(step, actions)
        actions.include?('place_token') && (
          step&.class&.name =~ /HomeToken|Home/i ||
          (step.respond_to?(:description) && step.description =~ /Home/i) ||
          (step.respond_to?(:home_token?) && step.home_token?)
        )
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

      def render_generic_choice(step, entity)
        return nil unless step && entity

        prompt = if step.respond_to?(:choice_name) && step.choice_name
                   step.choice_name
                 elsif step.respond_to?(:description) && step.description
                   step.description
                 else
                   'Choice:'
                 end

        raw_choices = begin
          if step.respond_to?(:choices_for)
            begin
              step.choices_for(entity)
            rescue ArgumentError
              step.choices_for
            end
          elsif step.respond_to?(:choices)
            begin
              step.choices(entity)
            rescue ArgumentError
              step.choices
            end
          end
        rescue StandardError
          nil
        end

        return nil unless raw_choices && !raw_choices.empty?

        label = prompt.to_s.strip
        label = "#{label}:" unless label.end_with?(':', '?')

        button_style = {
          padding: '0 12px',
          height: '1.65rem',
          fontSize: '0.85rem',
          fontWeight: 'bold',
          backgroundColor: '#f8fafc',
          color: '#0f172a',
          border: '1px solid #cbd5e1',
          borderRadius: '4px',
          cursor: 'pointer',
          boxShadow: '0 1px 2px rgba(0,0,0,0.05)',
          display: 'inline-flex',
          alignItems: 'center',
          justifyContent: 'center',
          lineHeight: '1',
        }

        buttons = if raw_choices.is_a?(Hash)
                    raw_choices.map do |val, text|
                      btn_click = -> { process_action(Engine::Action::Choose.new(entity, choice: val)) }
                      h(:button, {
                          style: button_style,
                          on: { click: btn_click },
                        }, text.to_s)
                    end
                  elsif raw_choices.is_a?(Array)
                    raw_choices.map do |val|
                      btn_click = -> { process_action(Engine::Action::Choose.new(entity, choice: val)) }
                      h(:button, {
                          style: button_style,
                          on: { click: btn_click },
                        }, val.to_s)
                    end
                  else
                    []
                  end

        return nil if buttons.empty?

        render_action_row(label, buttons)
      end

      def render_generic_fallback(step, entity, actions)
        return nil unless step && entity

        if step.respond_to?(:choices) || step.respond_to?(:choices_for)
          choice_node = render_generic_choice(step, entity)
          return choice_node if choice_node
        end

        unhandled = actions - %w[pass undo redo]
        return nil if unhandled.empty?

        desc = if step.respond_to?(:description) && step.description
                 step.description
               else
                 "Pending: #{unhandled.join(', ')}"
               end

        render_action_row('Action Required:', [
          h(:span, { style: { fontSize: '0.88rem', color: '#475569', fontStyle: 'italic' } }, desc),
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
          next false if @game.respond_to?(:entity_can_use_company?) && !@game.entity_can_use_company?(entity, c)

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

          c_hexes = resolve_target_hexes(c)
          wrap_node = render_railcard(
            card_text,
            %w[game-card action-buy clickable],
            click_handler,
            build_company_tooltip(c),
            nil,
            "cmd_company_#{c.id}",
            %w[cmd-company-wrapper status-company-wrapper]
          )
          if c_hexes.any?
            c_hex_names = c_hexes.map do |h|
              if h.respond_to?(:name) && h.name
                h.name.to_s
              else
                (h.respond_to?(:id) && h.id ? h.id.to_s : h.to_s)
              end
            end
            h(:div, {
                style: { display: 'inline-block' },
                on: {
                  mouseenter: lambda {
                    `window.highlightMapHexes && window.highlightMapHexes(#{c_hex_names})`
                    nil
                  },
                  mouseleave: lambda {
                    `window.clearMapHexHighlights && window.clearMapHexHighlights()`
                    nil
                  },
                },
              }, [wrap_node])
          else
            wrap_node
          end
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
        entity_id = entity&.id
        if Lib::Storage['cmd_last_entity_id']&.to_s != entity_id&.to_s
          Lib::Storage['cmd_last_entity_id'] = entity_id
          @routes = []
          store(:routes, @routes, skip: true)
          store(:show_manual_routes, false, skip: true)
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

        is_draft = step&.class&.name =~ /Draft/i ||
                   (step.respond_to?(:description) && step.description =~ /Draft/i) ||
                   (@game.respond_to?(:round) && @game.round.class.name =~ /Draft/i)

        is_home_token = home_token_step?(step, actions)

        phase = :waiting
        if actions.include?('lay_tile')
          phase = :build_track
        elsif is_home_token
          phase = :home_token
        elsif actions.include?('place_token')
          phase = :place_token
        elsif actions.include?('run_routes')
          phase = :run_routes
        elsif actions.include?('dividend') || actions.include?('payout') || actions.include?('withhold') || actions.include?('half') || actions.include?('split')
          phase = :dividend
        elsif actions.include?('buy_train')
          phase = :buy_train
        elsif actions.include?('buy_token')
          phase = :buy_token
        elsif actions.include?('issue_shares') || actions.include?('reissue_shares') || actions.include?('reissue')
          phase = :issue_shares
        elsif actions.include?('redeem_shares') || actions.include?('redeem')
          phase = :redeem
        elsif actions.include?('par') && (
          (step&.respond_to?(:corporation_pending_par) && step&.corporation_pending_par) ||
          (step&.respond_to?(:corporation) && step&.corporation) ||
          (step&.respond_to?(:par_corporation) && step&.par_corporation) ||
          (step&.respond_to?(:corporations) && step.corporations&.one?) ||
          (step&.current_entity || current_entity)&.corporation?
        )
          phase = :par
        elsif actions.include?('corporate_buy_shares') || actions.include?('buy_shares')
          phase = :buy_shares
        elsif is_draft
          phase = :choose
        elsif actions.include?('choose')
          phase = :choose
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
        if Lib::Storage[last_base_key]&.to_i != base_revenue
          Lib::Storage[storage_key] = base_revenue
          Lib::Storage[last_base_key] = base_revenue
        end

        current_revenue = Lib::Storage[storage_key].to_i
        formatted_revenue = @game.respond_to?(:format_revenue_currency) ? @game.format_revenue_currency(current_revenue) : @game.format_currency(current_revenue)

        if @game.finished
          return h(:div, { style: { display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', height: '100%' } }, [
            h(:div, { style: { fontSize: '2rem', fontWeight: 'bold', marginBottom: '1rem' } }, 'End of Game'),
            h(:button, {
                style: { padding: '1rem 2rem', fontSize: '1.2rem', backgroundColor: '#28a745', color: 'white', border: 'none', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold' },
                on: {
                  click: lambda {
                    Lib::Storage['show_results_overlay'] = true
                    update
                  },
                },
              }, 'Show Results'),
            (Lib::Storage['show_results_overlay'] ? h(View::Game::Dashboard::ResultsOverlay, game: @game) : nil),
          ].compact)
        end

        is_draft_round = is_draft ||
                          (@game.round.class.name =~ /Draft|Auction/i) ||
                          (step&.class&.name =~ /Draft|Auction|Waterfall/i)

        is_stock_round = begin
          @game.round.is_a?(Engine::Round::Stock)
        rescue StandardError
          false
        end ||
                         (@game.round.class.name =~ /Stock/i) ||
                         (@game.round.respond_to?(:stock?) && @game.round.stock?)

        player_display_name = active_player&.name || (entity.respond_to?(:name) ? entity.name : nil) || player_name

        if is_stock_round || is_draft_round || (entity.respond_to?(:player?) && entity.player?)
          zone_1 = h(:div, { style: { flex: '0 0 20%', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '0.5rem', borderRight: '1px solid #ccc', boxSizing: 'border-box' } }, [
            h(:div, { style: { fontSize: '1.6rem', fontWeight: 'bold', color: '#000000', textAlign: 'center', wordBreak: 'break-word', lineHeight: '1.2' } }, player_display_name),
          ])
        else
          phase_labels = {
            waiting: 'WAITING',
            build_track: 'LAY TILE',
            home_token: 'CHOOSE HOME',
            place_token: 'PLACE TOKEN',
            buy_token: 'BUY TOKENS',
            run_routes: 'RUN ROUTES',
            dividend: 'DIVIDEND',
            buy_train: 'BUY TRAIN',
            discard_train: 'DISCARD TRAIN',
            issue_shares: 'ISSUE SHARES',
            redeem: 'REDEEM SHARES',
            choose: (is_draft ? 'DRAFT' : 'CHOOSE'),
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
            ]),
          ])
        end

        show_manual_routes = @show_manual_routes || Lib::Storage['cmd_manual_routes'] == true || Lib::Storage['cmd_manual_routes'] == 'true'
        zone_2_content = []

        if phase == :run_routes
          if @cmd_router_running
            zone_2_content << h(:div, { style: { padding: '0.2rem', textAlign: 'center', color: '#666', fontStyle: 'italic', fontSize: '0.9rem' } }, '🔄 Computing optimal network tracks...')
          elsif show_manual_routes
            zone_2_content << render_action_row('Revenue:', [
              h(:div, { style: { fontSize: '1.2rem', fontWeight: 'bold', color: COLOR_MONEY, fontFamily: FONT_MONEY, minWidth: '4.5rem', textAlign: 'center', height: '1.8rem', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' } }, formatted_revenue),
              h(:button, {
                  style: {
                    padding: '0 8px',
                    height: '1.8rem',
                    fontSize: '0.8rem',
                    fontWeight: 'bold',
                    backgroundColor: '#64748b',
                    color: '#fff',
                    border: 'none',
                    borderRadius: '4px',
                    cursor: 'pointer',
                    marginLeft: '0.4rem',
                    display: 'inline-flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                  },
                  on: {
                    click: lambda {
                      store(:show_manual_routes, false)
                      Lib::Storage['cmd_manual_routes'] = false
                      update
                    },
                  },
                }, 'Close Manual'),
            ])
          else
            spinner_items = [
              h(:button, {
                  style: { width: '1.8rem', height: '1.8rem', fontSize: '1.1rem', fontWeight: 'bold', cursor: 'pointer', backgroundColor: '#e0e0e0', border: '1px solid #999', borderRadius: '4px', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', padding: '0', lineHeight: '1' },
                  on: {
                    click: lambda {
                      Lib::Storage[storage_key] = [current_revenue - 10, 0].max
                      update
                    },
                  },
                }, '-'),
              h(:div, { style: { fontSize: '1.2rem', fontWeight: 'bold', color: COLOR_MONEY, fontFamily: FONT_MONEY, minWidth: '4.5rem', textAlign: 'center', height: '1.8rem', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', lineHeight: '1' } }, formatted_revenue),
              h(:button, {
                  style: { width: '1.8rem', height: '1.8rem', fontSize: '1.1rem', fontWeight: 'bold', cursor: 'pointer', backgroundColor: '#e0e0e0', border: '1px solid #999', borderRadius: '4px', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', padding: '0', lineHeight: '1' },
                  on: {
                    click: lambda {
                      Lib::Storage[storage_key] = current_revenue + 10
                      update
                    },
                  },
                }, '+'),
              h(:button, {
                  style: {
                    padding: '0 8px',
                    height: '1.8rem',
                    fontSize: '0.8rem',
                    fontWeight: 'bold',
                    backgroundColor: '#2563eb',
                    color: '#fff',
                    border: 'none',
                    borderRadius: '4px',
                    cursor: 'pointer',
                    marginLeft: '0.4rem',
                    display: 'inline-flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    lineHeight: '1',
                  },
                  on: {
                    click: lambda {
                      store(:show_manual_routes, true)
                      Lib::Storage['cmd_manual_routes'] = true
                      update
                    },
                  },
                }, 'Calculate Manually'),
            ]

            zone_2_content << render_action_row('Revenue:', spinner_items)
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
          when :redeem then advance_text = 'Skip Redeem'
          when :par then advance_text = 'Skip Par'
          when :merge then advance_text = 'Done / Pass'
          when :loan then advance_text = 'Done / Pass'
          when :buy_shares then advance_text = 'Done / Pass'
          when :choose, :bid then advance_text = is_draft ? 'Pass / Blank' : 'Pass'
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
              extra_revenue: @game.extra_revenue(entity, routes_to_submit) + (current_revenue - base_revenue)
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

        has_abilities = !actions.include?('choose') && entity && (@game.companies || []).any? do |c|
          next false if c.respond_to?(:closed?) && c.closed?

          is_owner = c.owner == entity || (entity.respond_to?(:owner) && c.owner && c.owner == entity.owner)
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
          h(:style, {}, '
            .cmd-company-wrapper:hover .cmd-company-tooltip,
            .status-company-wrapper:hover .status-company-tooltip,
            .cmd-corp-wrapper:hover .cmd-corp-tooltip,
            .status-corp-wrapper:hover .status-corp-tooltip,
            .cmd-company-tooltip,
            .status-company-tooltip,
            .cmd-corp-tooltip,
            .status-corp-tooltip {
              display: none !important;
            }
          '),

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
        current_action_id = @game.respond_to?(:raw_actions) && @game.raw_actions ? @game.raw_actions.size : last_action_id
        routed_token = "#{entity&.id}_#{current_action_id}"

        if phase == :run_routes && @last_routed_action_id != routed_token && !@cmd_router_running
          store(:last_routed_action_id, routed_token, skip: true)
          store(:cmd_router_running, true, skip: false)

          @routes.each(&:reset!) if @routes&.any?
          @game.reset_adjustable_trains!(entity, @routes) if @game.respond_to?(:reset_adjustable_trains!)
          @routes = []
          store(:routes, @routes, skip: true)
          store(:selected_route, nil, skip: true)

          lambda {
            `setTimeout(function() {`
            begin
              flash_cb = lambda do |msg|
                store(:flash_opts, { message: msg }, skip: false)
              end
              router = Engine::AutoRouter.new(@game, flash_cb)
              router_entity = @game.current_entity || entity
              p_timeout = setting_for(:path_timeout).to_i
              p_timeout = 10_000 if p_timeout.zero?
              r_timeout = setting_for(:route_timeout).to_i
              r_timeout = 10_000 if r_timeout.zero?

              router.compute(
                router_entity,
                routes: [],
                path_timeout: p_timeout,
                route_timeout: r_timeout,
                callback: lambda do |computed_routes|
                  routes_list = computed_routes || []
                  store(:routes, routes_list, skip: true)
                  store(:selected_route, routes_list.first, skip: true)

                  auto_rev = 0
                  routes_list.each do |r|
                    auto_rev += r.revenue if r.chains.any?
                  rescue Engine::GameError, StandardError
                  end

                  storage_key = "rev_override_#{entity&.id}"
                  last_base_key = "last_base_rev_#{entity&.id}"
                  Lib::Storage[storage_key] = auto_rev
                  Lib::Storage[last_base_key] = auto_rev

                  store(:cmd_router_running, false)
                  update
                end
              )
            rescue Exception
              store(:cmd_router_running, false)
              update
            end
            `}, 50);`
          }.call
        end

        panel_bar = h(:div, { style: { display: 'flex', flexDirection: 'row', width: '100%', height: '100%', boxSizing: 'border-box', backgroundColor: '#fff', position: 'relative', zIndex: 99_999, overflow: 'visible' } }, [
          zone_1,
          zone_2,
          zone_3,
        ].compact)
        if show_manual_routes
          h(:div, { style: { width: '100%', height: '100%', position: 'relative' } }, [
            panel_bar,
            h(View::Game::Dashboard::ManualRouteOverlay, game: @game, entity: entity, routes: @routes, selected_route: @selected_route),
          ])
        else
          panel_bar
        end
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
                             on: {
                               click: lambda {
                                 Lib::Storage['show_merge_candidates'] = true
                                 update
                               },
                             },
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
                kwargs = target.respond_to?(:minor?) && target.minor? ? { minor: target } : { corporation: target }
                process_action(Engine::Action::Merge.new(entity, **kwargs))
              }
              render_railcard(target.name, %w[game-card action-buy clickable], click_handler)
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
              num_shares = if bundle.respond_to?(:num_shares)
                             bundle.num_shares
                           else
                             (bundle.respond_to?(:shares) ? bundle.shares.size : 1)
                           end
              pct = bundle.respond_to?(:percent) ? bundle.percent : (num_shares * 10)
              price = if bundle.respond_to?(:price)
                        bundle.price
                      else
                        (bundle.respond_to?(:share_price) ? bundle.share_price.price * num_shares : 0)
                      end

              click_handler = lambda {
                action_class = actions.include?('corporate_buy_shares') ? Engine::Action::CorporateBuyShares : Engine::Action::BuyShares
                process_action(action_class.new(entity, shares: bundle.respond_to?(:shares) ? bundle.shares : [bundle], share_price: bundle.respond_to?(:share_price) ? bundle.share_price : nil, percent: pct))
              }
              card = render_railcard("#{pct}%", %w[game-card action-buy clickable], click_handler)
              h(:div, { style: { display: 'inline-flex', alignItems: 'center', gap: '0.3rem', margin: '0 0.2rem' } }, [
                card,
                h(:span, { style: { fontFamily: FONT_MONEY, color: COLOR_MONEY, fontWeight: 'bold', fontSize: '0.85rem', whiteSpace: 'nowrap' } }, @game.format_currency(price)),
              ])
            end
            components << render_action_row('Buy Treasury Share:', buy_boxes)
          else
            components << render_action_row('Buy Treasury Share:', [h(:span, { style: { fontStyle: 'italic', color: '#666', fontSize: '0.85rem' } }, 'No shares available')])
          end
        end

        h(:div, { style: { display: 'flex', flexDirection: 'column', gap: '0.4rem', width: '100%' } }, components)
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

        corp_hexes = resolve_target_hexes(corporation)
        corp_badge_node = render_railcard(corporation.name, ['game-card'])
        corp_badge = if corp_hexes.any?
                       corp_hex_names = corp_hexes.map do |h|
                         if h.respond_to?(:name) && h.name
                           h.name.to_s
                         else
                           (h.respond_to?(:id) && h.id ? h.id.to_s : h.to_s)
                         end
                       end
                       h(:div, {
                           style: { display: 'inline-block' },
                           on: {
                             mouseenter: lambda {
                               `window.highlightMapHexes && window.highlightMapHexes(#{corp_hex_names})`
                               nil
                             },
                             mouseleave: lambda {
                               `window.clearMapHexHighlights && window.clearMapHexHighlights()`
                               nil
                             },
                           },
                         }, [corp_badge_node])
                     else
                       corp_badge_node
                     end

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
            slot = (@game.par_chart[price].index(nil) if @game.respond_to?(:par_chart) && @game.par_chart[price])
            args = { corporation: corporation, share_price: price }
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
                      elsif c.respond_to?(:max_price)
                        c.max_price
                      else
                        (entity.respond_to?(:cash) ? entity.cash : 0)
                      end

          company_click_handler = lambda {
            `var p = document.getElementById('railcard-portal'); if (p) { p.style.display = 'none'; p.innerHTML = ''; }`
            menu_title = "Buy #{c.name} from #{owner_name} (#{min_price}-#{max_price}):"
            default_price = [entity.respond_to?(:cash) ? entity.cash : min_price, max_price].min
            default_price = [default_price, min_price].max

            show_price_dialog(
              menu_title,
              min_price,
              max_price,
              default_price,
              lambda { |price_val|
                process_action(Engine::Action::BuyCompany.new(entity, company: c, price: price_val))
              }
            )
          }

          card_text = (c.sym || c.name).to_s
          tooltip = build_company_tooltip(c)
          wrapper_classes = tooltip ? %w[cmd-company-wrapper status-company-wrapper] : nil

          render_railcard(card_text, %w[game-card action-buy clickable], company_click_handler, tooltip, nil, nil, wrapper_classes, entity: c)
        end.compact

        return nil if company_boxes.empty?

        render_action_row('Buy Privates:', company_boxes)
      end

      def render_discard_trains(step, entity)
        return nil unless entity && step

        discardable = if step.respond_to?(:discardable_trains)
                        step.discardable_trains(entity)
                      elsif entity.respond_to?(:trains)
                        entity.trains
                      else
                        []
                      end

        train_boxes = (discardable || []).map do |train|
          click_handler = -> { process_action(Engine::Action::DiscardTrain.new(entity, train: train)) }
          render_railcard(train.name, %w[game-card action-sell clickable card-train], click_handler)
        end

        return nil if train_boxes.empty?

        render_action_row('Discard:', train_boxes)
      end

      def render_surrender_trains(actions, step, entity)
        return nil unless entity && step

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

        train_boxes = (trains || []).map do |train|
          click_handler = -> { process_action(action_class.new(entity, train: train)) }

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
            elsif (m = btn_text.match(/([+-]?\d+\w*)/))
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

          card = render_railcard(train.name, %w[game-card action-sell clickable card-train], click_handler)
          if cost_str.empty?
            card
          else
            h(:div, { style: { display: 'inline-flex', alignItems: 'center', gap: '0.3rem', margin: '0 0.2rem' } }, [
              card,
              h(:span, { style: { fontFamily: FONT_MONEY, color: '#dc2626', fontWeight: 'bold', fontSize: '0.85rem', whiteSpace: 'nowrap' } }, cost_str),
            ])
          end
        end

        return nil if train_boxes.empty?

        render_action_row('Surrender:', train_boxes)
      end

      def render_home_token_step(_step, entity)
        return nil unless entity

        target_hexes = resolve_target_hexes(entity)
        hex_info = target_hexes.any? ? " (#{target_hexes.join(', ')})" : ''

        hover_events = {}
        if target_hexes.any?
          hover_events = {
            mouseenter: lambda {
              `window.highlightMapHexes && window.highlightMapHexes(#{target_hexes})`
              nil
            },
            mouseleave: lambda {
              `window.clearMapHexHighlights && window.clearMapHexHighlights()`
              nil
            },
          }
        end

        instruction = h(:span, {
                          style: {
                            fontSize: '0.88rem',
                            color: '#1e293b',
                            fontWeight: '600',
                            display: 'inline-flex',
                            alignItems: 'center',
                            gap: '0.35rem',
                            cursor: target_hexes.any? ? 'pointer' : 'default',
                          },
                          on: hover_events,
                        }, [
          h(:span, { style: { fontSize: '1rem' } }, '📍'),
          h(:span, "Lay token#{hex_info}"),
        ])

        render_action_row('Home Token:', instruction)
      end

      def render_buy_tokens(step, entity)
        return nil unless entity && step

        tokens = if step.respond_to?(:buyable_tokens)
                   step.buyable_tokens(entity) || []
                 elsif step.respond_to?(:available_tokens)
                   step.available_tokens(entity) || []
                 elsif step.respond_to?(:tokens)
                   step.tokens(entity) || []
                 else
                   []
                 end

        return nil if tokens.empty?

        token_cost_fn = lambda do |num|
          if step.respond_to?(:token_cost)
            begin
              step.token_cost(entity) * num
            rescue ArgumentError
              step.token_cost * num
            end
          elsif step.respond_to?(:price_for_tokens)
            step.price_for_tokens(entity, num)
          elsif tokens.first.respond_to?(:price) && tokens.first.price
            tokens.first.price * num
          else
            0
          end
        end

        buttons = tokens.map.with_index(1) do |token, num|
          price = token_cost_fn.call(num)
          price_str = price.positive? ? @game.format_currency(price) : 'Free'
          can_afford = (entity.respond_to?(:cash) ? entity.cash : 0) >= price

          click_handler = lambda {
            process_action(Engine::Action::BuyToken.new(entity, token: token, price: price))
          }

          card_classes = %w[game-card action-buy]
          card_classes << 'clickable' if can_afford
          card = render_railcard(num.to_s, card_classes, (can_afford ? click_handler : nil))

          h(:div, { style: { display: 'inline-flex', alignItems: 'center', gap: '0.3rem', margin: '0 0.2rem' } }, [
            card,
            h(:span, {
                style: {
                  fontFamily: FONT_MONEY,
                  color: can_afford ? COLOR_MONEY : '#9ca3af',
                  fontWeight: 'bold',
                  fontSize: '0.85rem',
                  whiteSpace: 'nowrap',
                },
              }, price_str),
          ])
        end

        render_action_row('Number of Tokens to Buy:', buttons)
      end

      def render_buyable_trains(step, entity)
        return nil unless entity && step

        train_boxes = []
        depot = @game.depot

        step_buyable = (step.buyable_trains(entity) || [] if step.respond_to?(:buyable_trains))

        must_buy = if step.respond_to?(:must_buy_train?)
                     step.must_buy_train?(entity)
                   else
                     entity.respond_to?(:trains) && entity.trains.empty?
                   end

        if depot
          buyable_depot = if step_buyable
                            step_buyable.select do |t|
                              t.owner == depot || t.owner.nil? || t.owner == @game.bank ||
                                (depot.respond_to?(:depot_trains) && depot.depot_trains.include?(t))
                            end
                          else
                            [depot.upcoming.first].compact
                          end
          unique_depot_trains = buyable_depot.uniq { |t| [depot.discarded.include?(t) ? :pool : :bank, t.name] }

          unique_depot_trains.each do |train|
            variants = train.respond_to?(:names_to_prices) && train.names_to_prices && !train.names_to_prices.empty? ? train.names_to_prices : { train.name => train.price }
            is_pool = depot.discarded.include?(train)
            source_tag = is_pool ? 'Pool' : 'Bank'

            variants.each do |variant_name, price|
              can_afford = (entity.respond_to?(:cash) ? entity.cash : 0) >= price || must_buy
              next unless can_afford

              can_buy_step = if step.respond_to?(:can_buy_train?)
                               begin
                                 step.can_buy_train?(entity, train)
                               rescue ArgumentError
                                 begin
                                   step.can_buy_train?(entity)
                                 rescue ArgumentError
                                   step.can_buy_train?
                                 end
                               rescue StandardError
                                 true
                               end
                             else
                               true
                             end
              next unless can_buy_step

              variant_str = variant_name.to_s
              variant_param = (variant_str == train.name.to_s ? nil : variant_str)

              click_handler = lambda {
                process_action(Engine::Action::BuyTrain.new(entity, train: train, price: price, variant: variant_param))
              }
              train_classes = %w[game-card action-buy clickable card-train]
              card = render_railcard(variant_str, train_classes, click_handler)
              price_str = @game.format_currency(price)
              train_boxes << h(:div, { style: { display: 'flex', flexDirection: 'row', alignItems: 'center', gap: '0.4rem' } }, [
                card,
                h(:span, { style: { fontSize: '0.85rem', color: '#475569', fontWeight: 'bold', whiteSpace: 'nowrap' } }, source_tag),
                h(:span, { style: { fontFamily: FONT_MONEY, color: can_afford ? COLOR_MONEY : '#9ca3af', fontWeight: 'bold', fontSize: '0.85rem', whiteSpace: 'nowrap' } }, price_str),
              ])
            end
          end
        end

        corp_owner = lambda do |corp|
          step.respond_to?(:corp_owner) ? step.corp_owner(corp) : corp.owner
        end

        available_other = if step_buyable
                            step_buyable.reject { |t| buyable_depot&.include?(t) }.group_by(&:owner)
                          else
                            {}
                          end
        available_other = available_other.select do |owner, _|
          owner && owner != depot && owner != @game.bank && corp_owner.call(owner) == corp_owner.call(entity)
        end

        available_other.each do |c, trains|
          trains.uniq(&:name).each do |t|
            min_price = 1
            max_price = if step.respond_to?(:max_price)
                          step.max_price(entity, t)
                        else
                          (entity.respond_to?(:cash) ? entity.cash : 9999)
                        end

            train_click_handler = lambda {
              `var p = document.getElementById('railcard-portal'); if (p) { p.style.display = 'none'; p.innerHTML = ''; }`
              menu_title = "Buy #{t.name} from #{c.name} (#{min_price}-#{max_price}):"
              show_price_dialog(menu_title, min_price, max_price, min_price, lambda { |price_val|
                process_action(Engine::Action::BuyTrain.new(entity, train: t, price: price_val))
              })
            }
            card = render_railcard(t.name, %w[game-card action-buy clickable card-train], train_click_handler)
            train_boxes << h(:div, { style: { display: 'flex', flexDirection: 'row', alignItems: 'center', gap: '0.4rem' } }, [
              card,
              h(:span, { style: { fontSize: '0.85rem', color: '#475569', fontWeight: 'bold', whiteSpace: 'nowrap' } }, (c.id || c.name).to_s),
            ])
          end
        end

        return nil if train_boxes.empty?

        h(:div, {
            style: {
              display: 'flex',
              flexDirection: 'row',
              alignItems: 'flex-start',
              justifyContent: 'flex-start',
              gap: '0.4rem',
              width: '100%',
              maxWidth: '100%',
              margin: '0 auto',
            },
          }, [
          h(:span, {
              style: {
                fontSize: '0.92rem',
                fontWeight: 'bold',
                color: '#333',
                minWidth: '6.5rem',
                textAlign: 'left',
                flexShrink: '0',
                height: '1.45rem',
                display: 'inline-flex',
                alignItems: 'center',
              },
            }, 'Buy Train:'),
          h(:div, { style: { display: 'flex', flexDirection: 'column', alignItems: 'flex-start', gap: '0.3rem', width: '100%' } }, train_boxes),
        ])
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
                  else
                    (bundle.respond_to?(:shares) ? bundle.shares.size : 1)
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

            pct_str = bundle.respond_to?(:percent) && bundle.percent ? "#{bundle.percent}%" : "#{num}S"
            price_str = @game.format_currency(price)

            click_handler = lambda {
              actions = begin
                @game.round.actions_for(entity)
              rescue StandardError
                []
              end || []
              if actions.include?('issue_shares')
                process_action(Engine::Action::IssueShares.new(entity, bundle: bundle))
              elsif actions.include?('reissue_shares') && defined?(Engine::Action::ReissueShares)
                process_action(Engine::Action::ReissueShares.new(entity, bundle: bundle))
              elsif actions.include?('reissue') && defined?(Engine::Action::Reissue)
                process_action(Engine::Action::Reissue.new(entity, bundle: bundle))
              elsif actions.include?('corporate_sell_shares')
                process_action(Engine::Action::CorporateSellShares.new(entity, bundle: bundle))
              else
                process_action(Engine::Action::SellShares.new(
                  entity,
                  shares: bundle.respond_to?(:shares) ? bundle.shares : [bundle],
                  share_price: bundle.respond_to?(:share_price) ? bundle.share_price : entity.share_price,
                  percent: bundle.respond_to?(:percent) ? bundle.percent : 10
                ))
              end
            }

            card = render_railcard(pct_str, %w[game-card action-sell clickable], click_handler)
            h(:div, { style: { display: 'inline-flex', alignItems: 'center', gap: '0.3rem', margin: '0 0.2rem' } }, [
              card,
              h(:span, { style: { fontFamily: FONT_MONEY, color: COLOR_MONEY, fontWeight: 'bold', fontSize: '0.85rem', whiteSpace: 'nowrap' } }, price_str),
            ])
          end

          rows << render_action_row('Issue:', issue_buttons)
        elsif ((@game.round.actions_for(entity) || []) & %w[issue_shares reissue_shares reissue]).any?
          rows << render_action_row('Issue:', [
            h(:span, { style: { color: '#888', fontStyle: 'italic', fontSize: '0.85rem' } }, 'No issuable shares available'),
          ])
        end

        redeemable_bundles = begin
          if step.respond_to?(:redeemable_shares)
            begin
              step.redeemable_shares(entity)
            rescue ArgumentError
              step.redeemable_shares
            end
          elsif step.respond_to?(:redeemable_bundles)
            begin
              step.redeemable_bundles(entity)
            rescue ArgumentError
              step.redeemable_bundles
            end
          elsif @game.respond_to?(:redeemable_shares)
            @game.redeemable_shares(entity)
          elsif step.respond_to?(:buyable_shares)
            begin
              step.buyable_shares(entity)
            rescue ArgumentError
              step.buyable_shares
            end
          else
            []
          end
        rescue StandardError
          []
        end || []

        if redeemable_bundles.any?
          redeem_buttons = redeemable_bundles.map do |raw_bundle|
            bundle = raw_bundle.respond_to?(:to_bundle) && !raw_bundle.respond_to?(:num_shares) ? raw_bundle.to_bundle : raw_bundle
            num = if bundle.respond_to?(:num_shares)
                    bundle.num_shares
                  else
                    (bundle.respond_to?(:shares) ? bundle.shares.size : 1)
                  end
            pct_str = bundle.respond_to?(:percent) && bundle.percent ? "#{bundle.percent}%" : "#{num}S"
            price = if bundle.respond_to?(:price)
                      bundle.price
                    elsif bundle.respond_to?(:share_price) && bundle.share_price
                      bundle.share_price.price * num
                    elsif entity.respond_to?(:share_price) && entity.share_price
                      entity.share_price.price * num
                    else
                      0
                    end

            price_str = @game.format_currency(price)
            can_afford = (entity.respond_to?(:cash) ? entity.cash : 0) >= price

            click_handler = lambda {
              actions = begin
                @game.round.actions_for(entity)
              rescue StandardError
                []
              end || []
              if actions.include?('redeem_shares')
                process_action(Engine::Action::RedeemShares.new(entity, bundle: bundle))
              elsif actions.include?('redeem') && defined?(Engine::Action::Redeem)
                process_action(Engine::Action::Redeem.new(entity, bundle: bundle))
              elsif actions.include?('corporate_buy_shares')
                process_action(Engine::Action::CorporateBuyShares.new(
                  entity,
                  shares: bundle.respond_to?(:shares) ? bundle.shares : [bundle],
                  share_price: bundle.respond_to?(:share_price) && bundle.share_price ? bundle.share_price : (price / [num, 1].max),
                  percent: bundle.respond_to?(:percent) ? bundle.percent : (num * 10)
                ))
              else
                process_action(Engine::Action::BuyShares.new(
                  entity,
                  shares: bundle.respond_to?(:shares) ? bundle.shares : [bundle],
                  share_price: bundle.respond_to?(:share_price) && bundle.share_price ? bundle.share_price : (price / [num, 1].max),
                  percent: bundle.respond_to?(:percent) ? bundle.percent : (num * 10)
                ))
              end
            }

            card_classes = %w[game-card action-buy]
            card_classes << 'clickable' if can_afford
            card = render_railcard(pct_str, card_classes, (can_afford ? click_handler : nil))
            h(:div, { style: { display: 'inline-flex', alignItems: 'center', gap: '0.3rem', margin: '0 0.2rem' } }, [
              card,
              h(:span, { style: { fontFamily: FONT_MONEY, color: can_afford ? COLOR_MONEY : '#9ca3af', fontWeight: 'bold', fontSize: '0.85rem', whiteSpace: 'nowrap' } }, price_str),
            ])
          end

          rows << render_action_row('Redeem:', redeem_buttons)
        elsif ((@game.round.actions_for(entity) || []) & %w[redeem redeem_shares]).any?
          rows << render_action_row('Redeem:', [
            h(:span, { style: { color: '#888', fontStyle: 'italic', fontSize: '0.85rem' } }, 'No redeemable shares available'),
          ])
        end

        return nil if rows.empty?

        h(:div, { style: { display: 'flex', flexDirection: 'column', gap: '0.25rem', width: '100%' } }, rows.compact)
      end

      def render_ground_truth_actions(actions, step)
        return h(:div) if @game.finished

        return h(UpgradeOrDiscardTrains) if actions.include?('discard_train') && actions.include?('swap_train')

        if actions.include?('par')
          pending_corp = if step&.respond_to?(:corporation_pending_par) && step&.corporation_pending_par
                           step.corporation_pending_par
                         elsif step&.respond_to?(:corporation) && step&.corporation
                           step.corporation
                         elsif step&.respond_to?(:par_corporation) && step&.par_corporation
                           step.par_corporation
                         elsif step&.respond_to?(:parring) && step&.parring
                           step.parring
                         elsif step&.respond_to?(:corporations) && step.corporations&.one?
                           step.corporations.first
                         elsif (step&.current_entity || current_entity)&.corporation?
                           step&.current_entity || current_entity
                         end

          unless pending_corp
            transacted_company = nil
            %i[company last_company auctioning].each do |m|
              if step&.respond_to?(m) && (val = step.send(m))
                transacted_company = val if val.respond_to?(:abilities) || val.is_a?(Engine::Company)
                break if transacted_company
              end
            end

            if transacted_company
              shares_ability = begin
                transacted_company.abilities(:shares)
              rescue StandardError
                nil
              end
              if shares_ability&.respond_to?(:shares)
                share = begin
                  shares_ability.shares.first
                rescue StandardError
                  nil
                end
                pending_corp = share.corporation if share&.respond_to?(:corporation)
              end
            end

            unless pending_corp
              actor = step&.current_entity || current_entity
              player_actor = actor.respond_to?(:player?) && actor.player? ? actor : actor&.owner
              if player_actor&.respond_to?(:companies)
                player_actor.companies.each do |c|
                  shares_ability = begin
                    c.abilities(:shares)
                  rescue StandardError
                    nil
                  end
                  next unless shares_ability&.respond_to?(:shares)

                  share = begin
                    shares_ability.shares.first
                  rescue StandardError
                    nil
                  end
                  corp = share.corporation if share&.respond_to?(:corporation)
                  if corp && !corp.ipoed
                    pending_corp = corp
                    break
                  end
                end
              end
            end
          end

          return render_par_step(step, step&.current_entity || current_entity, pending_corp) if pending_corp
        end

        is_draft_or_auction = (step&.respond_to?(:auctioning) && step&.auctioning) ||
                              (!actions.include?('par') && (
                                (step&.class&.name =~ /Waterfall|Draft|Auction|Initial/i) ||
                                (step&.respond_to?(:description) && step.description =~ /Draft|Auction/i) ||
                                (@game.respond_to?(:round) && @game.round.class.name =~ /Draft|Auction/i)
                              ))

        case @game.round
        when Engine::Round::Stock
          if is_draft_or_auction
            h(View::Game::Dashboard::DraftOverlay, game: @game)
          elsif actions.include?('choose')
            render_generic_choice(step, step&.current_entity || current_entity)
          else
            Lib::Storage['selected_bid_corp'] = nil if Lib::Storage['selected_bid_corp']
            h(::View::Game::DashboardStock, game: @game)
          end
        when Engine::Round::Operating
          is_pure_merger_step = step.class.name =~ /Merge/i ||
                                 (actions.include?('merge') && (actions & %w[lay_tile place_token run_routes dividend buy_train]).empty?)

          if is_pure_merger_step
            h(:div, { style: { display: 'flex', flexDirection: 'column', gap: '0.15rem', width: '100%', alignItems: 'flex-start' } }, [render_merger_step(step, step&.current_entity || current_entity, actions)].compact)
          elsif actions.include?('buy_shares') && step&.current_entity&.player?
            h(::View::Game::DashboardStock, game: @game)
          elsif is_draft_or_auction
            h(View::Game::Dashboard::DraftOverlay, game: @game)
          else
            components = []
            convert_track = step&.respond_to?(:conversion?) && step&.conversion?
            loans_rendered = false

            if actions.include?('choose')
              choice_item = render_generic_choice(step, step&.current_entity || current_entity)
              components << choice_item if choice_item
            end

            components << h(SpecialBuy) if actions.include?('special_buy')
            components << h(TrackConversion) if actions.include?('run_routes') && convert_track
            components << h(Convert) if actions.include?('convert')
            components << h(SwitchTrains) if actions.include?('switch_trains')
            components << h(ReassignTrains) if actions.include?('reassign_trains')
            components << h(DoubleHeadTrains) if actions.include?('double_head_trains')
            components << h(CombinedTrains) if actions.include?('combined_trains')
            if actions.include?('lay_tile')
              components << render_action_row('Lay Tile:', h(:span, { style: { fontSize: '0.88rem', color: '#1e293b', fontWeight: '600' } }, ''))
            end
            if home_token_step?(step, actions)
              components << render_home_token_step(step, step&.current_entity || current_entity)
            elsif actions.include?('place_token')
              components << render_action_row('Place Token:', h(:span, { style: { fontSize: '0.85rem', color: '#475569', fontStyle: 'italic' } }, ''))
            end

            components << render_buy_tokens(step, step&.current_entity || current_entity) if actions.include?('buy_token')

            components << render_issue_shares(step, step&.current_entity || current_entity) if (%w[issue_shares reissue_shares reissue redeem redeem_shares] & actions).any?

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
              elsif (%w[issue_shares reissue_shares reissue redeem redeem_shares] & actions).none?
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

            can_buy_companies = actions.include?('buy_company') ||
                                (step.respond_to?(:buyable_companies) && step.buyable_companies(step&.current_entity)&.any?) ||
                                (step.respond_to?(:can_buy_company?) && @game.companies.any? { |c| step.can_buy_company?(step&.current_entity, c) })
            components << render_buyable_companies(step, step&.current_entity) if can_buy_companies

            components << render_buyable_trains(step, step&.current_entity) if actions.include?('buy_train')
            components << render_discard_trains(step, step&.current_entity) if actions.include?('discard_train')

            components << h(AcquireCompanies) if actions.include?('acquire_company')
            components << h(CorporateSellCompanies) if actions.include?('corporate_sell_company')
            components << h(CorporateBuyCompanies) if actions.include?('corporate_buy_company')

            if components.compact.empty?
              fallback_item = render_generic_fallback(step, step&.current_entity || current_entity, actions)
              components << fallback_item if fallback_item
            end

            h(:div, { style: { display: 'flex', flexDirection: 'column', gap: '0.15rem', width: '100%', alignItems: 'flex-start' } }, components.compact)
          end
        when Engine::Round::Choices
          if actions.include?('choose')
            choice_item = render_generic_choice(step, step&.current_entity || current_entity)
            choice_item ? h(:div, { style: { display: 'flex', flexDirection: 'column', gap: '0.15rem', width: '100%', alignItems: 'flex-start' } }, [choice_item]) : h(Round::Choices, game: @game)
          else
            h(Round::Choices, game: @game)
          end
        when Engine::Round::Auction, Engine::Round::Draft
          h(View::Game::Dashboard::DraftOverlay, game: @game)
        when Engine::Round::Merger
          if !(%w[buy_train scrap_train reassign_trains] & actions).empty? && @game.train_actions_always_use_operating_round_view?
            h(Round::Operating, game: @game)
          elsif (%w[merge convert buy_shares corporate_buy_shares take_loan payoff_loan] & actions).any?
            h(:div, { style: { display: 'flex', flexDirection: 'column', gap: '0.15rem', width: '100%', alignItems: 'flex-start' } }, [render_merger_step(step, step&.current_entity || current_entity, actions)].compact)
          elsif actions.include?('choose')
            choice_item = render_generic_choice(step, step&.current_entity || current_entity)
            choice_item ? h(:div, { style: { display: 'flex', flexDirection: 'column', gap: '0.15rem', width: '100%', alignItems: 'flex-start' } }, [choice_item]) : h(Round::Merger, game: @game)
          else
            h(Round::Merger, game: @game)
          end
        else
          if is_draft_or_auction
            h(View::Game::Dashboard::DraftOverlay, game: @game)
          elsif actions.include?('choose')
            choice_item = render_generic_choice(step, step&.current_entity || current_entity)
            h(:div, { style: { display: 'flex', flexDirection: 'column', gap: '0.15rem', width: '100%', alignItems: 'flex-start' } }, [choice_item].compact)
          elsif @game.round.stock?
            h(::View::Game::DashboardStock, game: @game)
          elsif @game.round.unordered?
            h(Round::Unordered, game: @game, user: nil)
          else
            render_generic_fallback(step, step&.current_entity || current_entity, actions) || h(:div)
          end
        end
      end
    end
  end
end

# rubocop:enable Layout/LineLength
