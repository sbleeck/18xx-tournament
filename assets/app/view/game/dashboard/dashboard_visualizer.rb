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

  def render_zoom_controls(panel_id, position_styles = {})
        pid = panel_id.to_s
        h(:div, {
          attrs: { class: 'panel-zoom-controls' },
          style: {
            position: 'absolute',
            zIndex: 20,
            display: 'flex',
            gap: '3px',
            backgroundColor: 'rgba(255,255,255,0.88)',
            padding: '2px 4px',
            borderRadius: '4px',
            border: '1px solid #ccc',
            boxShadow: '0 1px 3px rgba(0,0,0,0.15)',
          }.merge(position_styles),
        }, [
          h(:button, {
            style: { width: '20px', height: '20px', lineHeight: '16px', textAlign: 'center', fontSize: '13px', fontWeight: 'bold', cursor: 'pointer', backgroundColor: '#fff', border: '1px solid #999', borderRadius: '3px', padding: '0', color: '#333' },
            attrs: { title: 'Zoom In', type: 'button', onclick: "window.zoomPanel('#{pid}', 1.15); return false;" },
            on: { click: -> { `window.zoomPanel('#{pid}', 1.15)` } },
          }, '+'),
          h(:button, {
            style: { width: '20px', height: '20px', lineHeight: '16px', textAlign: 'center', fontSize: '13px', fontWeight: 'bold', cursor: 'pointer', backgroundColor: '#fff', border: '1px solid #999', borderRadius: '3px', padding: '0', color: '#333' },
            attrs: { title: 'Zoom Out', type: 'button', onclick: "window.zoomPanel('#{pid}', 0.85); return false;" },
            on: { click: -> { `window.zoomPanel('#{pid}', 0.85)` } },
          }, '−'),
          h(:button, {
            style: { width: '20px', height: '20px', lineHeight: '16px', textAlign: 'center', fontSize: '11px', fontWeight: 'bold', cursor: 'pointer', backgroundColor: '#fff', border: '1px solid #999', borderRadius: '3px', padding: '0', color: '#333' },
            attrs: { title: 'Reset to Fit', type: 'button', onclick: "window.resetPanelZoom('#{pid}'); return false;" },
            on: { click: -> { `window.resetPanelZoom('#{pid}')` } },
          }, '⟲'),
        ])
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

                          window.scalerScales = window.scalerScales || {};
                          window.scalerUserZoom = window.scalerUserZoom || { 'map-panel-bot': 1.0, 'panel-market': 1.0 };
                          window.scalerPanOffset = window.scalerPanOffset || {
                            'map-panel-bot': { x: 0, y: 0 },
                            'panel-market': { x: 0, y: 0 }
                          };

                          window.applyPanelTransform = function(panelId) {
                            var panel = document.getElementById(panelId);
                            if (!panel) return;
                            var wrapper = panel.querySelector('.scaler-content');
                            if (!wrapper) return;

                            var offset = (window.scalerPanOffset && window.scalerPanOffset[panelId]) || { x: 0, y: 0 };
                            wrapper.style.left = offset.x + 'px';
                            wrapper.style.top = offset.y + 'px';

                            var dynStyle = document.getElementById('dynamic-scaler-styles');
                            if (!dynStyle) return;
                            var css = '';
                            for (var id in window.scalerScales) {
                              var uZoom = (window.scalerUserZoom && window.scalerUserZoom[id]) || 1.0;
                              var effScale = window.scalerScales[id] * uZoom;
                              css += '#' + id + ' .scaler-content { transform: scale(' + effScale + ') !important; transform-origin: top left !important; }\n';
                            }
                            dynStyle.innerHTML = css;
                          };

                          window.zoomPanel = function(panelId, factor) {
                            window.scalerUserZoom = window.scalerUserZoom || {};
                            var cur = (window.scalerUserZoom && window.scalerUserZoom[panelId]) || 1.0;
                            window.scalerUserZoom[panelId] = Math.max(0.15, Math.min(4.0, cur * factor));
                            window.applyPanelTransform(panelId);
                          };

                          window.resetPanelZoom = function(panelId) {
                            window.scalerUserZoom = window.scalerUserZoom || {};
                            window.scalerPanOffset = window.scalerPanOffset || {};
                            window.scalerUserZoom[panelId] = 1.0;
                            window.scalerPanOffset[panelId] = { x: 0, y: 0 };
                            window.applyPanelTransform(panelId);
                          };

                          var createPanHandler = function(panelId) {
                            var panel = document.getElementById(panelId);
                            if (!panel) return;
                            var wrapper = panel.querySelector('.scaler-content');
                            if (!wrapper) return;

                            wrapper.style.position = 'absolute';
                            window.scalerPanOffset[panelId] = window.scalerPanOffset[panelId] || { x: 0, y: 0 };
                            window.scalerUserZoom[panelId] = window.scalerUserZoom[panelId] || 1.0;

                            var isPanning = false;
                            var startX = 0, startY = 0;

                            panel.style.cursor = 'grab';

                            panel.addEventListener('mousedown', function(e) {
                              if (e.button !== 0 || (e.target.closest && e.target.closest('.panel-zoom-controls'))) return;
                              isPanning = true;
                              var currentOffset = window.scalerPanOffset[panelId] || { x: 0, y: 0 };
                              startX = e.clientX - currentOffset.x;
                              startY = e.clientY - currentOffset.y;
                              panel.style.cursor = 'grabbing';
                            });

                            document.addEventListener('mousemove', function(e) {
                              if (!isPanning) return;
                              window.scalerPanOffset[panelId] = {
                                x: e.clientX - startX,
                                y: e.clientY - startY
                              };
                              wrapper.style.left = window.scalerPanOffset[panelId].x + 'px';
                              wrapper.style.top = window.scalerPanOffset[panelId].y + 'px';
                            });

                            document.addEventListener('mouseup', function() {
                              if (!isPanning) return;
                              isPanning = false;
                              panel.style.cursor = 'grab';
                            });

                            panel.addEventListener('dblclick', function(e) {
                              if (e.target.closest && e.target.closest('.panel-zoom-controls')) return;
                              window.resetPanelZoom(panelId);
                            });

                            panel.addEventListener('wheel', function(e) {
                              e.preventDefault();
                              var zoomDelta = e.deltaY < 0 ? 1.06 : 0.94;
                              var currentZ = (window.scalerUserZoom && window.scalerUserZoom[panelId]) || 1.0;
                              window.scalerUserZoom[panelId] = Math.max(0.15, Math.min(4.0, currentZ * zoomDelta));
                              window.applyPanelTransform(panelId);
                            }, { passive: false });
                          };

                          createPanHandler('map-panel-bot');
                          createPanHandler('panel-market');

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
                                  var requiredWidth = bbox.width + 50;
                                  var requiredHeight = bbox.height + 50;
                                  svg.setAttribute('viewBox', (bbox.x - 25) + ' ' + (bbox.y - 25) + ' ' + requiredWidth + ' ' + requiredHeight);
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
                                    var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
                                    var allG = svg.querySelectorAll('g');
                                    if (allG.length > 0) {
                                      for (var gi = 0; gi < allG.length; gi++) {
                                        try {
                                          var gb = allG[gi].getBBox();
                                          if (gb.width > 0 || gb.height > 0) {
                                            minX = Math.min(minX, gb.x);
                                            minY = Math.min(minY, gb.y);
                                            maxX = Math.max(maxX, gb.x + gb.width);
                                            maxY = Math.max(maxY, gb.y + gb.height);
                                          }
                                        } catch(err) {}
                                      }
                                    }
                                    if (svg.getBBox) {
                                      try {
                                        var sb = svg.getBBox();
                                        if (sb.width > 0 || sb.height > 0) {
                                          minX = Math.min(minX, sb.x);
                                          minY = Math.min(minY, sb.y);
                                          maxX = Math.max(maxX, sb.x + sb.width);
                                          maxY = Math.max(maxY, sb.y + sb.height);
                                        }
                                      } catch(err) {}
                                    }

                                    if (isFinite(maxX) && isFinite(maxY)) {
                                      var requiredWidth = (maxX - minX) + 24;
                                      var requiredHeight = (maxY - minY) + 40;
                                      svg.setAttribute('viewBox', (minX - 12) + ' ' + (minY - 10) + ' ' + requiredWidth + ' ' + requiredHeight);
                                      svg.style.overflow = 'visible';
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

                            for (var pId in window.scalerScales) {
                              window.applyPanelTransform(pId);
                            }
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
              render_zoom_controls('map-panel-bot', { top: '6px', left: '6px' }),
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
              render_zoom_controls('panel-market', { top: '6px', right: '6px' }),
              h(:div, { attrs: { class: 'scaler-content' }, style: { position: 'absolute', top: '0', left: '0', display: 'flex', flexDirection: 'column', width: 'max-content', height: 'max-content', transformOrigin: 'top left', margin: '0', padding: '0' } }, [
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