# frozen_string_literal: true

# rubocop:disable Layout/LineLength

module View
  module Game
    module Dashboard
      module RailcardHelper
        FONT_MONEY = '"Courier New", Courier, monospace'
        COLOR_MONEY = '#4c1d95'

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

          if (Array.isArray(wrapper_classes)) {
            var valid_classes = [];
            for (var j = 0; j < wrapper_classes.length; j++) {
              if (isPresent(wrapper_classes[j])) {
                valid_classes.push(wrapper_classes[j]);
              }
            }
            if (valid_classes.length > 0) {
              has_wrapper_classes = true;
              clean_wrapper_classes = valid_classes.join(' ');
            }
          } else if (isPresent(wrapper_classes)) {
            has_wrapper_classes = true;
            clean_wrapper_classes = String(wrapper_classes);
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