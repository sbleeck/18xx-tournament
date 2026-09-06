# frozen_string_literal: true

# rubocop:disable Layout/LineLength

module View
  module Game
    module Dashboard
      module RailcardHelper
        FONT_MONEY = '"Courier New", Courier, monospace'
        COLOR_MONEY = '#4c1d95'

        TOOLTIP_CSS = '
          .cmd-company-tooltip,
          .status-company-tooltip,
          .cmd-corp-tooltip,
          .status-corp-tooltip {
            display: none !important;
          }
        '

        def render_tooltip_style
          h(:style, {}, '
            .cmd-company-wrapper:hover .cmd-company-tooltip,
            .cmd-company-wrapper:hover .status-company-tooltip,
            .status-company-wrapper:hover .status-company-tooltip,
            .status-company-wrapper:hover .cmd-company-tooltip,
            .cmd-corp-wrapper:hover .cmd-corp-tooltip,
            .cmd-corp-wrapper:hover .status-corp-tooltip,
            .status-corp-wrapper:hover .status-corp-tooltip,
            .status-corp-wrapper:hover .cmd-corp-tooltip,
            .cmd-company-tooltip,
            .status-company-tooltip,
            .cmd-corp-tooltip,
            .status-corp-tooltip {
              display: none !important;
            }
          ')
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
                           corporation.respond_to?(:ipoed) && corporation.ipoed ? 'Unfloated (Parred)' : 'Unopened'
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

        def render_price_dialog(title, storage_key, min_price, max_price, on_confirm, on_cancel)
          stored = Lib::Storage[storage_key]
          val_i = stored ? stored.to_i : min_price
          val_i = min_price if val_i < min_price
          val_i = max_price if val_i > max_price
          current_val = val_i.to_s

          modal_box = h(:div, {
                          style: {
                            backgroundColor: '#ffffff',
                            border: '2px solid #333333',
                            borderRadius: '8px',
                            padding: '1.5rem',
                            boxShadow: '0px 10px 30px rgba(0,0,0,0.5)',
                            color: '#000000',
                            minWidth: '260px',
                            textAlign: 'center',
                            boxSizing: 'border-box',
                          },
                        }, [
            h(:div, { style: { fontSize: '0.85rem', fontWeight: 'bold', marginBottom: '0.8rem', whiteSpace: 'nowrap' } }, title),
            h(:input, {
                key: storage_key,
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
                  value: current_val,
                },
                attrs: {
                  type: 'number',
                  min: min_price.to_s,
                  max: max_price.to_s,
                },
                on: {
                  input: lambda { |event|
                    Lib::Storage[storage_key] = `#{event}.target.value`
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
                on: {
                  click: lambda {
                    price_value = Lib::Storage[storage_key].to_i
                    price_value = min_price if price_value < min_price
                    price_value = max_price if price_value > max_price

                    Lib::Storage[storage_key] = nil
                    on_confirm.call(price_value)
                  },
                },
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
                on: {
                  click: lambda {
                    Lib::Storage[storage_key] = nil
                    on_cancel.call
                  },
                },
              }, 'Cancel'),
          ])

          h(:div, {
              attrs: { id: "dialog_#{storage_key}" },
              style: {
                position: 'fixed',
                top: '0',
                left: '0',
                width: '100vw',
                height: '100vh',
                backgroundColor: 'rgba(0, 0, 0, 0.4)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                zIndex: '2147483647',
              },
            }, [modal_box])
        end

        def show_price_dialog(title, min_price, max_price, default_val, on_confirm, on_cancel = nil)
          %x{
            var existing = document.getElementById('railcard-dialog-portal');
            if (existing) { existing.remove(); }

            var overlay = document.createElement('div');
            overlay.id = 'railcard-dialog-portal';
            overlay.style.cssText = 'position:fixed;top:0;left:0;width:100vw;height:100vh;background:rgba(0,0,0,0.5);display:flex;align-items:center;justify-content:center;z-index:2147483647;box-sizing:border-box;';

            var box = document.createElement('div');
            box.style.cssText = 'background:#ffffff;border:2px solid #333333;border-radius:8px;padding:1.5rem;box-shadow:0px 12px 36px rgba(0,0,0,0.6);color:#000000;min-width:280px;max-width:90vw;text-align:center;box-sizing:border-box;';

            var titleEl = document.createElement('div');
            titleEl.style.cssText = 'font-size:0.95rem;font-weight:bold;margin-bottom:0.8rem;color:#111;word-break:break-word;';
            titleEl.innerText = #{title};
            box.appendChild(titleEl);

            var inputEl = document.createElement('input');
            inputEl.type = 'number';
            inputEl.min = String(#{min_price});
            inputEl.max = String(#{max_price});
            inputEl.value = String(#{default_val});
            inputEl.style.cssText = 'display:block;width:100%;margin-bottom:0.8rem;box-sizing:border-box;padding:6px 10px;font-size:1.1rem;font-family:"Courier New",Courier,monospace;font-weight:bold;color:#4c1d95;text-align:center;border:1px solid #999;border-radius:4px;';
            box.appendChild(inputEl);

            var confirmBtn = document.createElement('button');
            confirmBtn.innerText = 'Confirm';
            confirmBtn.style.cssText = 'display:block;width:100%;margin-bottom:0.4rem;cursor:pointer;font-size:0.85rem;font-weight:bold;padding:6px 12px;background-color:#007bff;border:1px solid #0056b3;color:#ffffff;border-radius:4px;';
            confirmBtn.onclick = function() {
              var val = parseInt(inputEl.value, 10);
              if (isNaN(val) || val < #{min_price}) val = #{min_price};
              if (val > #{max_price}) val = #{max_price};
              overlay.remove();
              if (#{on_confirm}) {
                if (typeof #{on_confirm} === 'function') {
                  #{on_confirm}(val);
                } else if (#{on_confirm}['$call']) {
                  #{on_confirm}['$call'](val);
                }
              }
            };
            box.appendChild(confirmBtn);

            var cancelBtn = document.createElement('button');
            cancelBtn.innerText = 'Cancel';
            cancelBtn.style.cssText = 'display:block;width:100%;cursor:pointer;font-size:0.85rem;padding:6px 12px;background-color:#e0e0e0;border:1px solid #999;border-radius:4px;color:#333;';
            cancelBtn.onclick = function() {
              overlay.remove();
              if (#{on_cancel}) {
                if (typeof #{on_cancel} === 'function') {
                  #{on_cancel}();
                } else if (#{on_cancel}['$call']) {
                  #{on_cancel}['$call']();
                }
              }
            };
            box.appendChild(cancelBtn);

            inputEl.onkeydown = function(e) {
              if (e.key === 'Enter') { confirmBtn.click(); }
              else if (e.key === 'Escape') { cancelBtn.click(); }
            };

            overlay.onclick = function(e) {
              if (e.target === overlay) { cancelBtn.click(); }
            };

            overlay.appendChild(box);
            document.body.appendChild(overlay);

            setTimeout(function() {
              inputEl.focus();
              inputEl.select();
            }, 50);
          }
          nil
        end

        def render_railcard(text, card_classes = ['game-card'], click_handler = nil, tooltip = nil, dropdown = nil, wrapper_id = nil, wrapper_classes = nil)
          classes = []
          if card_classes
            `if (Array.isArray(#{card_classes})) {`
            classes = card_classes
            `} else {`
            classes = [card_classes]
            `}`
          else
            classes = ['game-card']
          end

          classes_str = classes.join(' ')
          is_buy = classes.include?('action-buy')
          is_sell = classes.include?('action-sell')
          is_clickable = click_handler ? true : false

          border_color = if is_buy
                           '#16a34a'
                         elsif is_sell
                           '#dc2626'
                         else
                           '#888888'
                         end

          bg_color = if is_buy
                       '#e6f4ea'
                     elsif is_sell
                       '#fef2f2'
                     else
                       '#fdfbf7'
                     end

          %x(
          if (typeof window !== 'undefined' && !window._railcard_portal_installed) {
            var portal = document.getElementById('railcard-portal');
            if (!portal) {
              portal = document.createElement('div');
              portal.id = 'railcard-portal';
              document.body.appendChild(portal);
            }
            portal.style.cssText = 'position:fixed;top:12px;left:50%;transform:translateX(-50%);pointer-events:none !important;z-index:2147483647;display:none;width:320px;max-width:90vw;background:#ffffff;border:2px solid #333333;border-radius:6px;padding:8px;box-shadow:0 12px 36px rgba(0,0,0,0.5);color:#000000;text-align:left;box-sizing:border-box;white-space:normal;word-break:break-word;';

            window._railcard_portal_installed = true;

            var hidePortal = function() {
              var p = document.getElementById('railcard-portal');
              if (p && p.style.display !== 'none') {
                p.style.display = 'none';
                p.innerHTML = '';
              }
            };

            document.addEventListener('mouseover', function(e) {
              var wrapper = e.target.closest && e.target.closest('.cmd-company-wrapper, .status-company-wrapper, .cmd-corp-wrapper, .status-corp-wrapper');
              if (wrapper) {
                var tt = wrapper.querySelector('.cmd-company-tooltip, .status-company-tooltip, .cmd-corp-tooltip, .status-corp-tooltip');
                if (tt) {
                  var p = document.getElementById('railcard-portal');
                  if (p) {
                    p.innerHTML = tt.innerHTML;
                    p.style.display = 'block';
                  }
                }
              } else {
                hidePortal();
              }
            });

            document.addEventListener('mouseout', function(e) {
              var wrapper = e.target.closest && e.target.closest('.cmd-company-wrapper, .status-company-wrapper, .cmd-corp-wrapper, .status-corp-wrapper');
              if (wrapper) {
                var related = e.relatedTarget && e.relatedTarget.closest && e.relatedTarget.closest('.cmd-company-wrapper, .status-company-wrapper, .cmd-corp-wrapper, .status-corp-wrapper');
                if (related !== wrapper) {
                  hidePortal();
                }
              }
            });

            window.addEventListener('scroll', hidePortal, true);
            window.addEventListener('click', hidePortal, true);
          }
          )

          has_tooltip = tooltip ? true : false
          valid_classes = []
          valid_classes.concat(%w[cmd-company-wrapper status-company-wrapper cmd-corp-wrapper status-corp-wrapper]) if has_tooltip

          if wrapper_classes
            `if (Array.isArray(#{wrapper_classes})) {`
            wrapper_classes.each do |cls|
              if cls
                c_str = `String(#{cls})`
                valid_classes << c_str unless valid_classes.include?(c_str)
              end
            end
            `} else {`
            c_str = `String(#{wrapper_classes})`
            valid_classes << c_str unless valid_classes.include?(c_str)
            `}`
          end

          has_wrapper_classes = !valid_classes.empty?
          clean_wrapper_classes = valid_classes.join(' ')

          has_wrapper_id = wrapper_id && !wrapper_id.to_s.empty?
          clean_wrapper_id = wrapper_id.to_s if has_wrapper_id

          dropdown_items = []
          if dropdown
            `if (Array.isArray(#{dropdown})) {`
            dropdown_items = dropdown
            `} else {`
            dropdown_items = [dropdown]
            `}`
          end
          has_dropdown = !dropdown_items.empty?

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
            children.concat(dropdown_items) if has_dropdown

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
