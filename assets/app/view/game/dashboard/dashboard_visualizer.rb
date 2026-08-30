# frozen_string_literal: true

# rubocop:disable Layout/LineLength

require 'view/game/actionable'
require 'view/game/dashboard/dashboard_command_column'
require 'view/game/dashboard/dashboard_map'
require 'view/game/dashboard/dashboard_entity_order'
require 'view/game/dashboard/dashboard_game_status'
require 'view/game/dashboard/dashboard_stock_market'
require 'view/game/history_and_undo'

module View
  module Game
    class DashboardVisualizer < Snabberb::Component
      needs :game
      needs :game_data, store: true
      needs :tile_selector, default: nil
      needs :routes, store: true, default: []
      needs :user, default: nil
      include Actionable

      def active_entity
        @game.round.active_step&.current_entity
      rescue NotImplementedError, StandardError
        nil
      end

      def active_player
        entity = active_entity
        return nil unless entity

        if entity.player?
          entity
        elsif entity.respond_to?(:player) && entity.player
          entity.player
        else
          entity.owner
        end
      end

      def render
        if @game.respond_to?(:finished?) && @game.finished?
          return h(:div, {
                     style: { display: 'flex', flexDirection: 'row', width: '100vw', height: '100vh', padding: '0.5rem', boxSizing: 'border-box', backgroundColor: '#ffffff', gap: '0.75rem' },
                   }, [
            h(:div, { style: { width: '55%', height: '100%', display: 'flex', flexDirection: 'column', gap: '0.5rem', overflow: 'hidden' } }, [
              h(:div, { style: { flex: '1 1 auto', border: '1px solid #ccc', borderRadius: '4px', display: 'flex', justifyContent: 'center', alignItems: 'center', overflow: 'hidden' } }, [
                h(:div, { attrs: { class: 'scaler-content' }, style: { display: 'flex', justifyContent: 'center', alignItems: 'center' } }, [
                  h(View::Game::DashboardMap, game: @game, user: @user, minimal: true),
                ]),
              ]),
            ]),
            h(:div, { style: { width: '45%', display: 'flex', flexDirection: 'column', height: '100%', gap: '0.5rem' } }, [
              h(:div, { style: { flex: '1 1 62%', border: '1px solid #ccc', padding: '2rem', borderRadius: '4px', textAlign: 'center', fontFamily: '"Helvetica Neue", Helvetica, Arial, sans-serif' } }, [
                h(:h3, 'Final Match State'),
                h(:p, 'The 1846 game has concluded. Active turn components and ledgers are disabled.'),
              ]),
              h(:div, { style: { flex: '1 1 30%', minHeight: '0', border: '1px solid #ccc', padding: '0.5rem', borderRadius: '4px', display: 'flex', justifyContent: 'center', alignItems: 'flex-start', overflow: 'hidden' } }, [
                h(:div, { attrs: { class: 'scaler-content' }, style: { width: 'max-content', height: 'max-content', minWidth: '100%', display: 'flex', justifyContent: 'center', alignItems: 'flex-start', transformOrigin: 'center top' } }, [
                  h(View::Game::DashboardStockMarket, game: @game),
                ]),
              ]),
            ]),
          ])
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
            hook: {
              insert: lambda {
                        `document.body.style.overflow = 'hidden'`
                        `document.body.style.margin = '0'`
                        `document.body.style.padding = '0'`
                        `document.body.style.backgroundColor = '#ffffff'`
                        `document.getElementById('app') && Object.assign(document.getElementById('app').style, { overflow: 'hidden', padding: '0', margin: '0', maxWidth: '100vw', width: '100vw', height: '100vh', backgroundColor: '#ffffff' })`
                        `document.getElementById('game') && Object.assign(document.getElementById('game').style, { overflow: 'hidden', width: '100vw', height: '100vh', maxWidth: '100vw', maxHeight: '100vh' })`

                        %x(window.init18xxResizers = function() {
                          var createResizer = function(resizerId, prevId, nextId, isVertical) {
                            var resizer = document.getElementById(resizerId);
                            var prev = document.getElementById(prevId);
                            var next = document.getElementById(nextId);
                            if(!resizer || !prev || !next) return;
                            var x = 0, y = 0, prevFlex = 0, nextFlex = 0;
                            var mouseDownHandler = function(e) {
                              x = e.clientX; y = e.clientY;
                              var prevRect = prev.getBoundingClientRect();
                              var nextRect = next.getBoundingClientRect();
                              prevFlex = isVertical ? prevRect.height : prevRect.width;
                              nextFlex = isVertical ? nextRect.height : nextRect.width;
                              document.addEventListener('mousemove', mouseMoveHandler);
                              document.addEventListener('mouseup', mouseUpHandler);
                              document.body.style.cursor = isVertical ? 'row-resize' : 'col-resize';
                            };
                            var mouseMoveHandler = function(e) {
                              var delta = isVertical ? (e.clientY - y) : (e.clientX - x);
                              var totalFlex = prevFlex + nextFlex;
                              var newPrevFlex = Math.max(0, prevFlex + delta);
                              var newNextFlex = Math.max(0, totalFlex - newPrevFlex);
                              
                              prev.style.flex = '0 0 ' + newPrevFlex + 'px';
                              next.style.flex = '1 1 auto';
                              
                              if (!isVertical) {
                                prev.style.height = '100%';
                                next.style.height = '100%';
                              }
                            };
                            var mouseUpHandler = function() {
                              document.removeEventListener('mousemove', mouseMoveHandler);
                              document.removeEventListener('mouseup', mouseUpHandler);
                              document.body.style.cursor = '';
                            };
                            resizer.addEventListener('mousedown', mouseDownHandler);
                          };
                          
                          createResizer('resizer-v-main', 'col-left', 'col-right', false);
                          createResizer('resizer-h-cmd-map', 'command-space-top', 'map-panel-bot', true);
                          createResizer('resizer-h-ledger-market', 'panel-ledger', 'panel-market', true);

                          var styleTag = document.getElementById('dashboard-map-svg-styles');
                          if (!styleTag) {
                            styleTag = document.createElement('style');
                            styleTag.id = 'dashboard-map-svg-styles';
                            styleTag.innerHTML = '.scaler-content text { font-size: 0.65em !important; letter-spacing: normal !important; } ' +
                                                 '.scaler-content .tile__text { font-size: 0.75em !important; } ' +
                                                 '.scaler-content text.number { font-size: 0.55em !important; }';
                            document.head.appendChild(styleTag);
                          }

                          var fitObserver = new ResizeObserver(function(entries) {
                            var dynStyle = document.getElementById('dynamic-scaler-styles');
                            if (!dynStyle) {
                              dynStyle = document.createElement('style');
                              dynStyle.id = 'dynamic-scaler-styles';
                              document.head.appendChild(dynStyle);
                            }
                            window.scalerScales = window.scalerScales || {};

                            for (var i = 0; i < entries.length; i++) {
                              var panel = entries[i].target;
                              if (!panel.id) continue;
                              var wrapper = panel.querySelector('.scaler-content');
                              if (!wrapper) continue;

                              var cw = wrapper.scrollWidth;
                              var ch = wrapper.scrollHeight;

                              if (panel.id === 'map-panel-bot') {
                                var svg = wrapper.querySelector('svg');
                                var topG = svg ? svg.querySelector('g') : null;
                                if (svg && topG) {
                                  var bbox = topG.getBBox();
                                  var requiredWidth = bbox.x + bbox.width + 50;
                                  var requiredHeight = bbox.y + bbox.height + 50;
                                  svg.setAttribute('width', requiredWidth);
                                  svg.setAttribute('height', requiredHeight);
                                  svg.style.width = requiredWidth + 'px';
                                  svg.style.height = requiredHeight + 'px';
                                  wrapper.style.width = requiredWidth + 'px';
                                  wrapper.style.height = requiredHeight + 'px';
                                  cw = requiredWidth;
                                  ch = requiredHeight;
                                }
                              }

                              if (panel.id === 'panel-market') {
                                var innerChild = wrapper.firstElementChild;
                                if (innerChild) {
                                  var svg = innerChild.tagName && innerChild.tagName.toLowerCase() === 'svg' ? innerChild : innerChild.querySelector('svg');
                                  if (svg) {
                                    var topG = svg.querySelector('g');
                                    if (topG) {
                                      var bbox = topG.getBBox();
                                      var requiredWidth = bbox.x + bbox.width + 20;
                                      var requiredHeight = bbox.y + bbox.height + 20;
                                      svg.setAttribute('width', requiredWidth);
                                      svg.setAttribute('height', requiredHeight);
                                      svg.style.width = requiredWidth + 'px';
                                      svg.style.height = requiredHeight + 'px';
                                      wrapper.style.width = requiredWidth + 'px';
                                      wrapper.style.height = requiredHeight + 'px';
                                      cw = requiredWidth;
                                      ch = requiredHeight;
                                    }
                                  } else {
                                    cw = innerChild.scrollWidth;
                                    ch = innerChild.scrollHeight;
                                    wrapper.style.width = cw + 'px';
                                    wrapper.style.height = ch + 'px';
                                  }
                                }
                              }

                              var pw = entries[i].contentRect.width - 16;
                              var ph = entries[i].contentRect.height - 16;

                              if (cw > 0 && ch > 0) {
                                window.scalerScales[panel.id] = Math.min(pw / cw, ph / ch);
                              }
                            }

                            var css = '';
                            for (var id in window.scalerScales) {
                              css += '#' + id + ' .scaler-content { transform: scale(' + window.scalerScales[id] + ') !important; transform-origin: top left !important; }\n';
                            }
                            dynStyle.innerHTML = css;
                          });

                          ['map-panel-bot', 'panel-ledger', 'panel-market'].forEach(function(id) {
                            var el = document.getElementById(id);
                            if (el) fitObserver.observe(el);
                          });
                        };
                        setTimeout(window.init18xxResizers, 200);)
                      },
              destroy: lambda {
                        `document.body.style.backgroundColor = ''`
                        `document.getElementById('app') && Object.assign(document.getElementById('app').style, { overflow: '', padding: '', margin: '', maxWidth: '', width: '', height: '', backgroundColor: '' })`
                        `document.getElementById('game') && Object.assign(document.getElementById('game').style, { overflow: '', width: '', height: '', maxWidth: '', maxHeight: '' })`
                       },
            },
            attrs: { id: 'viz-master-frame' },
            style: {
              display: 'flex',
              flexDirection: 'row',
              width: '100vw',
              height: '100vh',
              maxHeight: '100vh',
              boxSizing: 'border-box',
              position: 'relative',
              overflow: 'hidden',
              padding: '0.5rem',
              backgroundColor: '#ffffff',
            },
          }, [
          # COLUMN 1 (LEFT): COMMAND SPACE (TOP) + MAP CANVAS (BOTTOM)
          h(:div, { attrs: { id: 'col-left' }, style: { flex: '0 0 55%', height: '100%', display: 'flex', flexDirection: 'column', overflow: 'hidden' } }, [
        # Command Row (Flexible height controlled by resizer)
            h(:div, { attrs: { id: 'command-space-top' }, style: { flex: '0 0 7.5rem', minHeight: '4.5rem', border: '1px solid #ccc', borderRadius: '4px', backgroundColor: '#fff', display: 'flex', flexDirection: 'column', overflow: 'hidden', boxSizing: 'border-box' } }, [
              h(:div, { style: { padding: '0.2rem', height: '100%', boxSizing: 'border-box', overflowY: 'hidden' } }, [
                h(View::Game::DashboardCommandColumn, game: @game),
              ]),
            ]),

            # Horizontal Resizer between Command Space and Map
            h(:div, { attrs: { id: 'resizer-h-cmd-map' }, style: { flex: '0 0 0.5rem', cursor: 'row-resize', zIndex: 10 } }),

            # Map Panel Box
            h(:div, { attrs: { id: 'map-panel-bot' }, style: { flex: '1 1 auto', border: '1px solid #ccc', borderRadius: '4px', backgroundColor: '#fff', overflow: 'hidden', position: 'relative' } }, [   
          
          
          
          h(:div, { attrs: { class: 'scaler-content' }, style: { position: 'absolute', top: '0', left: '0', width: 'max-content', height: 'max-content', transformOrigin: 'top left' } }, [
                h(View::Game::DashboardMap, game: @game, user: @user),
              ]),
            ]),
          ]),

          # VERTICAL RESIZER
          h(:div, { attrs: { id: 'resizer-v-main' }, style: { flex: '0 0 0.75rem', cursor: 'col-resize', zIndex: 10 } }),

          # COLUMN 2 (RIGHT): GLOBAL CONTROLS, TURN ORDER & DATA LEDGERS
          h(:div, { attrs: { id: 'col-right' }, style: { flex: '1 1 auto', display: 'flex', flexDirection: 'column', height: '100%', maxHeight: '100%', overflow: 'hidden', gap: '0.5rem' } }, [
            
           # Entity Turn Tracker Hub
            h(:div, { attrs: { id: 'temporal-hub' }, style: { flex: '0 0 auto', display: 'flex', flexDirection: 'column', border: '1px solid #ccc', borderRadius: '4px', backgroundColor: '#f8f9fa', padding: '0.25rem', minHeight: '2.8rem', overflowX: 'auto' } }, [
              if @game.respond_to?(:finished?) && @game.finished?
                h(View::Game::DashboardEntityOrder, round: nil)
              else
                h(View::Game::DashboardEntityOrder, round: @game.round)
              end,
            ]),

            # Status Table & Cash / Trains Ledger
            h(:div, { attrs: { id: 'panel-ledger' }, style: { flex: '1 1 auto', overflow: 'hidden', border: '1px solid #ccc', padding: '0.4rem', borderRadius: '4px', backgroundColor: '#fff', display: 'flex', flexDirection: 'column' } }, [
              h(:div, { attrs: { class: 'scaler-content' }, style: { display: 'flex', flexDirection: 'column', width: 'max-content', minWidth: '100%', transformOrigin: 'top left' } }, [
                h(View::Game::DashboardGameStatus, game: @game)
              ]),
            ]),

            # Horizontal Resizer
            h(:div, { attrs: { id: 'resizer-h-ledger-market' }, style: { flex: '0 0 0.5rem', cursor: 'row-resize', zIndex: 10 } }),

            # Stock Market Grid
            h(:div, { attrs: { id: 'panel-market' }, style: { flex: '1 1 auto', minHeight: '0', overflow: 'hidden', border: '1px solid #ccc', padding: '0.5rem', borderRadius: '4px', backgroundColor: '#fff', boxSizing: 'border-box', position: 'relative' } }, [
              h(:div, { attrs: { class: 'scaler-content' }, style: { display: 'flex', flexDirection: 'column', width: 'max-content', height: 'max-content', minWidth: '100%', transformOrigin: 'top left', margin: '0', padding: '0' } }, [
                h(View::Game::DashboardStockMarket, game: @game),
              ]),
            ]),
          ]),
        ])
      end
    end
  end
end
# rubocop:enable Layout/LineLength