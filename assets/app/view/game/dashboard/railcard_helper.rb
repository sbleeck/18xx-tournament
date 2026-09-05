# frozen_string_literal: true

# rubocop:disable Layout/LineLength

module View
  module Game
    module Dashboard
      module RailcardHelper
        def render_railcard(*args)
          is_status_call = `Array.isArray(#{args[1]})`

          if is_status_call
            # DashboardGameStatus convention:
            # (text, classes, click_handler, tooltip, dropdowns, wrapper_id, wrapper_classes)
            text = args[0]
            card_classes = args[1]
            click_handler = args[2]
            tooltip = args[3]
            dropdown = args[4]
            wrapper_id = args[5]
            wrapper_classes = args[6]
            disabled = false
            color_border = nil
          else
            # DashboardCommandColumn convention:
            # (entity, text, subtext, color, click_handler, tooltip, dropdown, disabled)
            _entity = args[0]
            text = args[1]
            subtext = args[2]
            color = args[3]
            click_handler = args[4]
            tooltip = args[5]
            dropdown = args[6]
            disabled = args[7] || false

            card_classes = ['game-card']
            card_classes << 'action-buy' if color == '#28a745' || color == '#16a34a'
            card_classes << 'action-sell' if color == '#dc2626'
            card_classes << 'clickable' if click_handler && !disabled

            color_border = color
            text = "#{text} #{subtext}".strip if subtext
            wrapper_id = nil
            wrapper_classes = tooltip ? ['cmd-company-wrapper'] : nil
          end

          # Native JavaScript Opal-aware truthiness and presence inspector
          is_buy = false
          is_sell = false
          is_disabled = false
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

          is_disabled = (disabled === true);
          is_clickable = isPresent(click_handler) && !is_disabled;

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
          } else if (isPresent(color_border)) {
            border_color = color_border;
          }

          // Tooltip validation
          if (isPresent(tooltip)) {
            has_tooltip = true;
          }

          // Dropdown / menu items validation
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

          // Wrapper ID validation
          if (isPresent(wrapper_id) && String(wrapper_id).length > 0) {
            has_wrapper_id = true;
            clean_wrapper_id = String(wrapper_id);
          }

          // Wrapper classes validation
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
            cursor: is_disabled ? 'not-allowed' : (is_clickable ? 'pointer' : 'default'),
            opacity: is_disabled ? '0.6' : '1',
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
            }, children)
          else
            card
          end
        end
      end
    end
  end
end

# rubocop:enable Layout/LineLength