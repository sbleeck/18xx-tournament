# frozen_string_literal: true

# rubocop:disable Layout/LineLength

module View
  module Game
    module Dashboard
      module RailcardHelper
        FONT_MONEY = '"Courier New", Courier, monospace'
        COLOR_MONEY = '#4c1d95'

        TOOLTIP_CSS = '
          .cmd-company-wrapper:hover .cmd-company-tooltip,
          .cmd-company-wrapper:hover .status-company-tooltip,
          .status-company-wrapper:hover .status-company-tooltip,
          .status-company-wrapper:hover .cmd-company-tooltip,
          .cmd-corp-wrapper:hover .cmd-corp-tooltip,
          .cmd-corp-wrapper:hover .status-corp-tooltip,
          .status-corp-wrapper:hover .status-corp-tooltip,
          .status-corp-wrapper:hover .cmd-corp-tooltip,
          .cmd-company-wrapper:hover .status-corp-tooltip,
          .status-company-wrapper:hover .cmd-corp-tooltip,
          .cmd-corp-wrapper:hover .cmd-company-tooltip,
          .status-corp-wrapper:hover .cmd-company-tooltip {
            display: block !important;
          }
          .cmd-company-wrapper:hover,
          .status-company-wrapper:hover,
          .cmd-corp-wrapper:hover,
          .status-corp-wrapper:hover {
            z-index: 99999 !important;
          }
        '

        def render_tooltip_style
          h(:style, {}, TOOLTIP_CSS)
        end

        def render_company_tooltip(title, subtitle, desc, val, rev, owner)
          h(:div, {
            attrs: { class: 'status-company-tooltip cmd-company-tooltip' },
            style: {
              display: 'none',
              position: 'fixed',
              top: '50%',
              left: '50%',
              transform: 'translate(-50%, -50%)',
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
              whiteSpace: 'normal',
              wordBreak: 'break-word',
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
            h(:div, { style: { fontSize: '0.78rem', lineHeight: '1.25', marginBottom: '6px', color: '#222222', whiteSpace: 'normal', wordBreak: 'break-word' } }, desc),
            h(:div, { style: { display: 'flex', justifyContent: 'space-between', fontSize: '0.78rem', fontWeight: 'bold', borderTop: '1px solid #ddd', paddingTop: '4px', marginBottom: '2px' } }, [
              h(:span, ['Value: ', h(:span, { style: { fontFamily: FONT_MONEY, fontWeight: 'bold', color: COLOR_MONEY } }, val)]),
              h(:span, ['Revenue: ', h(:span, { style: { fontFamily: FONT_MONEY, fontWeight: 'bold', color: COLOR_MONEY } }, rev)]),
            ]),
            h(:div, { style: { fontSize: '0.78rem', fontWeight: 'bold', textAlign: 'center', color: '#555555' } }, "Owner: #{owner}"),
          ])
        end

        def build_company_tooltip(c)
          owner_name = c.owner&.name || 'Bank'
          desc_text = if c.respond_to?(:desc) && c.desc && !c.desc.empty?
                        c.desc
                      elsif c.respond_to?(:abilities) && c.abilities&.any?
                        c.abilities.map { |a| a.respond_to?(:description) ? a.description : nil }.compact.join(' ')
                      else
                        'No special abilities.'
                      end

          value_str = @game.format_currency(c.value || 0)
          revenue_str = @game.format_currency(c.revenue || 0)

          render_company_tooltip('Private Company', c.name, desc_text, value_str, revenue_str, owner_name)
        end

        def render_corp_tooltip(corporation)
          return nil unless corporation

          owner_name = corporation.owner ? corporation.owner.name : 'Unowned / Bank'
          corp_type = if corporation.minor?
                        'Minor Corporation'
                      elsif corporation.respond_to?(:type) && corporation.type == :national
                        'National Railway'
                      else
                        'Major Corporation'
                      end

          is_minor = corporation.respond_to?(:minor?) && corporation.minor?
          is_unopened = !is_minor && corporation.respond_to?(:floated?) && !corporation.floated?
          status_label = if is_minor
                           corporation.owner ? 'Operating' : 'Available'
                         elsif is_unopened
                           (corporation.respond_to?(:ipoed) && corporation.ipoed) ? 'Unfloated (Parred)' : 'Unopened'
                         else
                           'Operating'
                         end
          market_price_str = corporation.share_price ? @game.format_currency(corporation.share_price.price) : 'Not on Market'
          par_price_str = corporation.respond_to?(:par_price) && corporation.par_price ? @game.format_currency(corporation.par_price.price) : 'Not Parred'

          cash_str = is_unopened ? '0' : @game.format_currency(corporation.cash || 0)

          details = []
          details << "Status: #{status_label}"
          details << "President / Owner: #{owner_name}"
          details << "Treasury: #{cash_str}"
          details << "Market Price: #{market_price_str} | Par: #{par_price_str}"

          if corporation.respond_to?(:float_percent) && corporation.float_percent
            shares_needed = corporation.respond_to?(:percent_to_float) ? "#{corporation.percent_to_float}% remaining" : ''
            details << "Float Rule: #{corporation.float_percent}% #{'(' + shares_needed + ')' if is_unopened && !shares_needed.empty?}"
          end

          if corporation.respond_to?(:tokens) && corporation.tokens.any?
            token_costs = corporation.tokens.map { |t| t.price ? @game.format_currency(t.price) : 'Free' }.join(', ')
            details << "Tokens: #{corporation.tokens.size} (#{token_costs})"
          end

          if corporation.respond_to?(:coordinates) && corporation.coordinates
            home_hex = Array(corporation.coordinates).join(', ')
            details << "Home Hex: #{home_hex}"
          end

          abilities_text = []
          if corporation.respond_to?(:abilities) && corporation.abilities&.any?
            corporation.abilities.each do |a|
              desc = a.respond_to?(:description) ? a.description : nil
              abilities_text << desc if desc && !desc.empty?
            end
          end

          h(:div, {
            attrs: { class: 'status-corp-tooltip cmd-corp-tooltip' },
            style: {
              display: 'none',
              position: 'fixed',
              top: '50%',
              left: '50%',
              transform: 'translate(-50%, -50%)',
              width: '320px',
              backgroundColor: '#ffffff',
              border: '2px solid #333333',
              borderRadius: '6px',
              padding: '10px',
              boxShadow: '0 8px 24px rgba(0,0,0,0.35)',
              zIndex: '99999',
              pointerEvents: 'none',
              color: '#000000',
              textAlign: 'left',
              boxSizing: 'border-box',
              whiteSpace: 'normal',
              fontWeight: 'normal',
            },
          }, [
            h(:div, {
              style: {
                backgroundColor: corporation.color || '#4c1d95',
                color: corporation.text_color || '#ffffff',
                fontWeight: 'bold',
                fontSize: '0.85rem',
                textAlign: 'center',
                padding: '3px 6px',
                marginBottom: '6px',
                textTransform: 'uppercase',
                borderRadius: '3px',
                border: '1px solid #333',
              },
            }, corp_type),
            h(:div, { style: { fontWeight: 'bold', fontSize: '1rem', textAlign: 'center', marginBottom: '6px', color: '#111' } }, "#{corporation.name} (#{corporation.id})"),
            h(:div, { style: { borderTop: '1px solid #ddd', paddingTop: '6px', marginBottom: '6px' } },
              details.map { |d| h(:div, { style: { fontSize: '0.78rem', marginBottom: '3px', color: '#222' } }, "• #{d}") }),
            (if abilities_text.any?
               h(:div, { style: { borderTop: '1px solid #ddd', paddingTop: '4px', marginTop: '4px' } }, [
                 h(:div, { style: { fontSize: '0.78rem', fontWeight: 'bold', color: '#b91c1c', marginBottom: '2px' } }, 'Special Abilities / Details:'),
                 *abilities_text.map { |ab| h(:div, { style: { fontSize: '0.75rem', color: '#333', lineHeight: '1.2' } }, ab) },
               ])
             end),
          ].compact)
        end

        def build_entity_tooltip(entity)
          return nil unless entity

          if entity.respond_to?(:company?) && entity.company?
            build_company_tooltip(entity)
          elsif (entity.respond_to?(:corporation?) && entity.corporation?) ||
                (entity.respond_to?(:minor?) && entity.minor?) ||
                entity.is_a?(Engine::Corporation) ||
                entity.is_a?(Engine::Minor)
            render_corp_tooltip(entity)
          end
        end

        def render_railcard(text, card_classes = ['game-card'], click_handler = nil, tooltip = nil, dropdown = nil, wrapper_id = nil, wrapper_classes = nil)
          is_buy = false
          is_sell = false
          is_clickable = false
          border_color = '#888888'
          bg_color = '#fdfbf7'
          classes_str = 'game-card'

          has_tooltip = false
          has_dropdown = false
          dropdown_items = []
          has_wrapper_id = false
          clean_wrapper_id = ''
          has_wrapper_classes = false
          clean_wrapper_classes = ''

          `

          if (typeof window !== 'undefined' && !window._railcard_portal_installed) {
            window._railcard_portal_installed = true;
            var portal = document.createElement('div');
            portal.id = 'railcard-portal';
            portal.style.cssText = 'position:fixed;top:0;left:0;width:100vw;height:100vh;pointer-events:none;z-index:2147483647;display:none;align-items:center;justify-content:center;';
            document.body.appendChild(portal);

            document.addEventListener('mouseover', function(e) {
              var wrapper = e.target.closest && e.target.closest('.cmd-company-wrapper, .status-company-wrapper, .cmd-corp-wrapper, .status-corp-wrapper');
              if (wrapper) {
                var tt = wrapper.querySelector('.cmd-company-tooltip, .status-company-tooltip, .cmd-corp-tooltip, .status-corp-tooltip');
                if (tt) {
                  portal.innerHTML = tt.outerHTML;
                  var inner = portal.firstElementChild;
                  if (inner) {
                    inner.classList.remove('cmd-company-tooltip', 'status-company-tooltip', 'cmd-corp-tooltip', 'status-corp-tooltip');
                    inner.style.display = 'block';
                    inner.style.position = 'relative';
                    inner.style.top = 'auto';
                    inner.style.left = 'auto';
                    inner.style.transform = 'none';
                    inner.style.margin = 'auto';
                    inner.style.boxShadow = '0 16px 48px rgba(0,0,0,0.5)';
                  }
                  portal.style.display = 'flex';
                }
              }
            });

            document.addEventListener('mouseout', function(e) {
              var wrapper = e.target.closest && e.target.closest('.cmd-company-wrapper, .status-company-wrapper, .cmd-corp-wrapper, .status-corp-wrapper');
              if (wrapper) {
                var related = e.relatedTarget && e.relatedTarget.closest && e.relatedTarget.closest('.cmd-company-wrapper, .status-company-wrapper, .cmd-corp-wrapper, .status-corp-wrapper');
                if (related !== wrapper) {
                  portal.style.display = 'none';
                  portal.innerHTML = '';
                }
              }
            });
          }
            
          function isPresent(val) {
            return val !== undefined && val !== null && val !== false && val !== Opal.nil;
          }

          is_clickable = isPresent(click_handler);

          var classes = [];
          if (Array.isArray(card_classes)) {
            classes = card_classes;
          } else if (isPresent(card_classes)) {
            classes = [card_classes];
          }

          is_buy = classes.indexOf('action-buy') !== -1;
          is_sell = classes.indexOf('action-sell') !== -1;
          classes_str = classes.join(' ');

          if (is_buy) {
            border_color = '#16a34a';
            bg_color = '#e6f4ea';
          } else if (is_sell) {
            border_color = '#dc2626';
            bg_color = '#fef2f2';
          }

          if (isPresent(tooltip)) {
            has_tooltip = true;
          }

          if (Array.isArray(dropdown)) {
            for (var i = 0; i < dropdown.length; i++) {
              if (isPresent(dropdown[i])) {
                dropdown_items.push(dropdown[i]);
                has_dropdown = true;
              }
            }
          } else if (isPresent(dropdown)) {
            dropdown_items.push(dropdown);
            has_dropdown = true;
          }

          if (isPresent(wrapper_id) && String(wrapper_id).length > 0) {
            has_wrapper_id = true;
            clean_wrapper_id = String(wrapper_id);
          }

          var valid_classes = [];
          if (has_tooltip) {
            valid_classes.push('cmd-company-wrapper');
            valid_classes.push('status-company-wrapper');
            valid_classes.push('cmd-corp-wrapper');
            valid_classes.push('status-corp-wrapper');
          }

          if (Array.isArray(wrapper_classes)) {
            for (var j = 0; j < wrapper_classes.length; j++) {
              if (isPresent(wrapper_classes[j])) {
                var cls = String(wrapper_classes[j]);
                if (valid_classes.indexOf(cls) === -1) {
                  valid_classes.push(cls);
                }
              }
            }
          } else if (isPresent(wrapper_classes)) {
            var single_cls = String(wrapper_classes);
            if (valid_classes.indexOf(single_cls) === -1) {
              valid_classes.push(single_cls);
            }
          }

          if (valid_classes.length > 0) {
            has_wrapper_classes = true;
            clean_wrapper_classes = valid_classes.join(' ');
          }
          `

          style_props = {
            minWidth: '3.2rem',
            height: '1.45rem',
            padding: '0 4px',
            margin: '2px',
            boxSizing: 'border-box',
            display: 'inline-flex',
            alignItems: 'center',
            justifyContent: 'center',
            borderRadius: '4px',
            fontSize: '0.85rem',
            fontFamily: '"Helvetica Neue", Helvetica, Arial, sans-serif',
            color: '#000000',
            backgroundColor: bg_color,
            border: "2px solid #{border_color}",
            cursor: is_clickable ? 'pointer' : 'default',
            whiteSpace: 'nowrap',
          }

          card_props = {
            attrs: { class: classes_str },
            style: style_props,
          }
          card_props[:on] = { click: click_handler } if is_clickable

          card = h(:div, card_props, text.to_s)

          needs_wrapper = has_tooltip || has_dropdown || has_wrapper_id || has_wrapper_classes

          if needs_wrapper
            w_attrs = {}
            w_attrs[:id] = clean_wrapper_id if has_wrapper_id
            w_attrs[:class] = clean_wrapper_classes if has_wrapper_classes

            children = []
            children << tooltip if has_tooltip
            children << card

            if has_dropdown
              `for (var k = 0; k < dropdown_items.length; k++) {`
                children << `dropdown_items[k]`
              `}`
            end

            h(:div, {
              attrs: w_attrs,
              style: { display: 'inline-block', position: 'relative' },
            }, children.compact)
          else
            card
          end
        end
      end
    end
  end
end

# rubocop:enable Layout/LineLength