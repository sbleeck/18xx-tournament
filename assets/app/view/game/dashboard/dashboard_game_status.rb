# frozen_string_literal: true

# rubocop:disable Layout/LineLength

module Engine
  class Minor
    def par_via_exchange
      nil
    end
  end
end

module Engine
  class Minor
    def par_via_exchange
      nil
    end

    def needs_token_to_par
      false
    end
  end
end

require 'lib/settings'
require 'lib/storage'
require 'view/link'
require 'view/share_calculation'
require 'view/game/bank'
require 'view/game/stock_market'
require 'view/game/tranches'
require 'view/game/actionable'
require 'lib/truncate'
require 'view/game/dashboard/row_animation'
require 'view/game/dashboard/dashboard_bank'
require 'view/game/dashboard/dashboard_upcoming_trains'
require 'view/game/dashboard/dashboard_card_animation'
require 'view/game/dashboard/dashboard_money_animation'
require 'view/game/dashboard/dashboard_card_animation'
require 'view/game/dashboard/railcard_helper'
require 'view/game/dashboard/par_prompt_overlay'

FLOATED = 2
UNFLOATED = 1
UNSTARTED = 0

module View
  module Game
    class DashboardGameStatus < Snabberb::Component
      include Lib::Settings
      include Actionable
      include View::ShareCalculation
      include View::Game::Dashboard::RailcardHelper
      needs :game, store: true
      needs :game_data, store: true

      PLAYER_COL_MAX_WIDTH = '4.5rem'

      FONT_STD = '"Helvetica Neue", Helvetica, Arial, sans-serif'
      FONT_MONEY = '"Courier New", Courier, monospace'
      COLOR_MONEY = '#4c1d95'
      FONT_CASH = '"Arial Black", Gadget, sans-serif'
      COLOR_CASH = '#4b0082' # Dark Purple (Indigo)
      COLOR_BANK = '#f5cda8'
      COLOR_ACTIVE = '#ffffff'
      COLOR_INACTIVE = '#e0e0e0'
      COLOR_MAUVE = '#dda0dd'

      def active_entity
        @game.round.active_step&.current_entity
      end

      def active_player
        entity = active_entity
        entity&.player? ? entity : entity&.owner
      end

      def display_players
        @game.players.sort_by { |p| p.id.to_s }
      end

      def render
        @spreadsheet_sort_by = Lib::Storage['spreadsheet_sort_by']
        @spreadsheet_sort_order = Lib::Storage['spreadsheet_sort_order']
        @hide_not_floated = Lib::Storage['spreadsheet_hide_not_floated']
        @show_privates = @game.respond_to?(:game_phases) && @game.game_phases.any? do |p|
          p[:status]&.any? do |s|
            s.include?('can_buy_companies')
          end
        end

        css = <<~CSS
                                                                                                                                            :root {
                                                                                                                                              --font-money: 'Courier New', monospace;
                                                                                                                                              --font-standard: "Helvetica Neue", Helvetica, Arial, sans-serif;
                                                                                                                                              --color-money-text: #4c1d95;
                                                                                                                                              --accent-action-color: #2563eb;
                                                                                                                                              --pulse-opacity-min: 0.75;
                                                                                                                                              --pulse-scale-duration: 2s;
                                                                                                                                              --opacity-unopened-row: 0.45;
                                                                                                                                              --bg-active-row: #ffffff;
                                                                                                                                               --bg-market-zone: #e6f4ea; /* Soft Sage Green */
                                                                                                                                              --bg-corporate-zone: #f3e8ff;
                                                                                                                                              --action-buy-edge: #16a34a;
                                                                                                                                              --action-sell-edge: #dc2626;
                                                                                                                                              --shadow-card: 0 1px 3px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.24);
                                                                                                                                            }
                                                                                #spreadsheet table { border-collapse: collapse; border: 3px solid #333333; background-color: #{COLOR_INACTIVE}; }
                                                                      #spreadsheet th, #spreadsheet td { border: 1px solid #b3b3b3 !important; vertical-align: middle !important; padding: 4px 2px !important; }
                                                                                                    #spreadsheet thead tr:last-child th { border-bottom: 3px solid #333333 !important; }
                                                                                                    #spreadsheet tr.last-player-row th, #spreadsheet tr.last-player-row td { border-bottom: 3px solid #333333 !important; }
                                                                                                    #spreadsheet tr.last-minor-row th, #spreadsheet tr.last-minor-row td { border-bottom: 3px solid #333333 !important; }
                                                                                                              .thick-right { border-right: 3px solid #333333 !important; }
                                                                                                    .no-border { border: none !important; }
                                                                                                                                .money-value, .padded_number { text-align: right !important; padding-right: 0.5rem !important; }
                                                  .money-value { font-family: var(--font-money) !important; font-weight: bold !important; color: var(--color-money-text) !important; font-variant-numeric: tabular-nums !important; }

                                        .game-card { display: inline-flex; align-items: center; justify-content: center; box-sizing: border-box; min-width: 3.5rem; height: 1.45rem; font-size: 0.85rem; padding: 0 4px; margin: 2px; border: 1px solid #888888; border-radius: 4px; background-color: #fdfbf7; color: #000000; box-shadow: var(--shadow-card); transition: transform 0.1s ease; font-family: var(--font-standard); }
                                                                                                              .game-card.clickable:hover { cursor: pointer; transform: translateY(-1px); box-shadow: 0 2px 5px rgba(0,0,0,0.2); }
                    .game-card.action-sell { border: 2px solid var(--action-sell-edge) !important; background-color: #fef2f2 !important; box-shadow: 0 0 0 1px var(--action-sell-edge) !important; }


                                                                                                            .game-card.action-buy { border: 2px solid var(--action-buy-edge) !important; background-color: #e6f4ea !important; box-shadow: 0 0 0 1px var(--action-buy-edge) !important; }                                                  #{'                                         '}
                                                                                                                                          .sell-restricted { text-decoration: line-through !important; opacity: 0.5 !important; cursor: not-allowed !important; }
                                                                                                                                          .token-bond { display: inline-block; width: 12px; height: 12px; background-color: #b91c1c; border-radius: 2px; }
                                                                                                                                          .align-top { vertical-align: top !important; }


                                                                  tr.active-turn-focus { background-color: var(--bg-active-row) !important; animation: zeroJankPulse var(--pulse-scale-duration) infinite ease-in-out; }                                                                                                   tr.active-turn-focus th, tr.active-turn-focus td { box-shadow: inset 0 3px 0 var(--accent-action-color), inset 0 -3px 0 var(--accent-action-color) !important; }
                                                                                                                                          tr.active-turn-focus th:first-child, tr.active-turn-focus td:first-child { box-shadow: inset 3px 3px 0 var(--accent-action-color), inset 0 -3px 0 var(--accent-action-color) !important; }
                                                                                                                                          tr.active-turn-focus th:last-child, tr.active-turn-focus td:last-child { box-shadow: inset -3px 3px 0 var(--accent-action-color), inset 0 -3px 0 var(--accent-action-color) !important; }
                                                                                                    #{'                                         '}
                                                                                                                                          @keyframes zeroJankPulse { 0% { opacity: 1; } 50% { opacity: var(--pulse-opacity-min); } 100% { opacity: 1; } }

                                                                                                                                          tr.company-row-unfloated, tr.company-row-closed { opacity: var(--opacity-unopened-row) !important; filter: grayscale(40%) !important; }
          tr.company-row-unfloated:hover, tr.company-row-closed:hover { opacity: 1 !important; filter: none !important; }
          tr.active-turn-focus:hover { animation: none !important; opacity: 1 !important; }
                                                                                                                                          .column-zone-market { background-color: var(--bg-market-zone) !important; }
          .column-zone-corporate { background-color: var(--bg-corporate-zone) !important; }
          tr.active-turn-focus td.column-zone-market, tr.active-turn-focus td.column-zone-corporate { background-color: var(--bg-active-row) !important; }
                      th.column-zone-corporate { background-color: #e9d5ff !important; color: #4c1d95 !important; }
          .status-corp-wrapper:hover { z-index: 99999; }
          .status-corp-tooltip, .status-company-tooltip, .cmd-corp-tooltip, .cmd-company-tooltip { display: none !important; }
          #{'          '}
        CSS

        h(:div, [
            h('div#spreadsheet', {
                style: {
                  overflow: 'auto',
                  marginTop: '1rem',
                },
              },
              [h(:style, css), render_corporation_table]),
          ])
      end

      def render_corporation_table
        h(:table, table_props, [
          h(:thead, render_titles),
          h(:tbody, render_corporations + render_player_rows),
        ])
      end

      def render_player_rows
        rows = []

        # 1. Cash Row
        cash_cells = [h('th.left', 'Cash')]
        display_players.each_with_index do |p, idx|
          clean_cash = @game.format_currency(p.cash)
          bg_color = p == active_player ? COLOR_ACTIVE : COLOR_INACTIVE
          is_last = idx == @game.players.size - 1
          cash_cells << h("td.padded_number.money-value#{'.thick-right' if is_last}",
                          { hook: Lib::MoneyAnimation.hook, style: { backgroundColor: bg_color } }, clean_cash)
        end
        rows << cash_cells

        # 2. Certs Row
        props = { style: { color: 'red' } }
        cert_cells = [h('th.left', 'Cert')]
        display_players.each_with_index do |player, idx|
          cert_limit = @game.cert_limit(player)

          bg_color = player == active_player ? COLOR_ACTIVE : COLOR_INACTIVE
          num_certs = @game.num_certs(player)
          cell_props = num_certs > cert_limit ? props.merge(style: { backgroundColor: bg_color }) : { style: { backgroundColor: bg_color } }
          is_last = idx == @game.players.size - 1
          cert_cells << h("td.padded_number#{'.thick-right' if is_last}", cell_props, "#{num_certs}/#{cert_limit}")
        end
        rows << cert_cells

        # 3. Loans Row
        if @game.respond_to?(:player_loans)
          loans_cells = [h('th.left', 'Loans')]
          display_players.each_with_index do |p, idx|
            bg_color = p == active_player ? COLOR_ACTIVE : COLOR_INACTIVE
            is_last = idx == @game.players.size - 1
            loans_cells << h("td.padded_number#{'.thick-right' if is_last}", { style: { backgroundColor: bg_color } },
                             @game.player_loans(p))
          end
          rows << loans_cells
        end

        # 5. Companies Row (Renamed to Privates)
        comp_cells = [h('th.left', 'Privates')]
        display_players.each_with_index do |p, idx|
          bg_color = p == active_player ? COLOR_ACTIVE : COLOR_INACTIVE
          is_last = idx == @game.players.size - 1
          comp_cells << render_companies(p, bg_color, is_last: is_last)
        end
        rows << comp_cells

        # Append the bank / extra information cell container to the first row
        rows[0] << h(:td, {
                       attrs: { rowspan: rows.size, colspan: 30, class: 'no-border' },
                       style: {
                         backgroundColor: '#ffffff',
                         verticalAlign: 'top',
                         paddingLeft: '1.5rem',
                         textAlign: 'left',
                       },
                     }, [render_extra_cards])

        rows.map.with_index do |row_cells, idx|
          props = tr_default_props
          props[:attrs] ||= {}
          props[:attrs][:class] = 'last-player-row' if idx == rows.size - 1
          h(:tr, props, row_cells)
        end
      end

      def render_corporations
        current_round = @game.turn_round_num
        corps = sorted_corporations

        corps.map.with_index do |corp_array, idx|
          current_corp = corp_array[1]
          next_corp = corps[idx + 1]&.last
          is_last_minor = current_corp.minor? && next_corp && !next_corp.minor?

          render_corporation(current_corp, corp_array[0], current_round, is_last_minor)
        end
      end

      def render_player_table
        h('div#player_table', { style: { float: 'left', marginRight: '1rem' } }, [
          h(:table, table_props, [
            h(:thead),
            h('tbody#player_details', [
              render_player_cash,
              render_player_loans,
              render_player_companies,
              render_player_certs,
            ]),
          ]),
        ])
      end

      def render_extra_cards
        children = []
        train_handler = lambda do |train, price = nil, variant = nil|
          owner_entity = train.owner
          if owner_entity.respond_to?(:owner) # Corporate train
            owner_key = owner_entity.respond_to?(:id) ? owner_entity.id : 'depot'
            Lib::Storage["cmd_buy_train_menu_#{owner_key}_#{train.id}"] = true
            Lib::Storage["cmd_buy_train_price_#{owner_key}_#{train.id}"] = active_entity.cash
            update
          else # Bank/Depot train at fixed value
            price_to_pay = price || train.price
            variant_name = variant ? variant.to_s : train.name.to_s
            variant_param = (variant_name == train.name.to_s ? nil : variant_name)

            clean_variant_id = variant_name.tr('/', '_')
            escaped_train_id = `CSS.escape('bank_train_' + #{train.id} + '_' + #{clean_variant_id})`
            escaped_dest_id = `CSS.escape('trains_' + #{active_entity.id})`
            source_selector = "##{escaped_train_id} .game-card"
            source_fallback = "##{`CSS.escape('bank_train_' + #{train.id})`} .game-card"
            target_selector = "##{escaped_dest_id}"

            active_source = `document.querySelector(#{source_selector}) ? #{source_selector} : #{source_fallback}`

            Lib::CardAnimation.fly(active_source, target_selector) do
              process_action(Engine::Action::BuyTrain.new(
                active_entity,
                train: train,
                price: price_to_pay,
                variant: variant_param
              ))
            end
          end
        end

        children << h(DashboardBank, game: @game, train_handler: train_handler)

        children << h(Tranches, game: @game) if @game.respond_to?(:tranches)
        children << h(DashboardUpcomingTrains, game: @game)
        h('div#extra_cards', { style: { marginBottom: '1rem' } }, children.compact)
      end

      def render_titles
        th_props = lambda do |cols, border_right = true|
          props = tr_default_props
          props[:attrs] = { colspan: cols }
          props[:style][:padding] = '0.3rem'
          props[:style][:borderRight] = "1px solid #{color_for(:font2)}" if border_right
          props[:style][:fontSize] = '1.1rem'
          props[:style][:letterSpacing] = '1px'
          props
        end

        treasury = []
        treasury << h('th.column-zone-corporate', {}, render_sort_link('Treasury', :treasury)) if @game.separate_treasury?

        extra = []
        if @game.respond_to?(:capitalization_type_desc)
          @is_escrow_game = @game.all_corporations.any? do |c|
            @game.capitalization_type_desc(c)&.include?('Escrow')
          end
          header_label = @is_escrow_game ? 'Escrow' : 'Capitalization'
          extra << h('th.column-zone-corporate', {}, render_sort_link(header_label, :capitalization_type_desc))
        end
        extra << h('th.column-zone-corporate', {}, render_sort_link('Loans', :loans)) if @game.total_loans&.nonzero?
        extra << h('th.column-zone-corporate', {}, render_sort_link('Shorts', :shorts)) if @game.respond_to?(:available_shorts)

        if (@diff_corp_sizes = @game.all_corporations.any? { |c| @game.corporation_size(c) != :small })
          extra << h('th.column-zone-corporate', {}, render_sort_link('Size', :corp_size))
        end
        @extra_size = extra.size

        corporation_props_size = (@show_privates ? 5 : 4) + extra.size + treasury.size

        players_title = h('th.thick-right', th_props[display_players.size], 'Players')

        pool_th_props = th_props[2]
        pool_th_props[:attrs][:class] = 'column-zone-market'
        pool_title = h('th.thick-right', pool_th_props, 'Pool')

        ipo_th_props = th_props[2]
        ipo_th_props[:attrs][:class] = 'column-zone-market'
        ipo_title = h('th.thick-right', ipo_th_props, @game.ipo_name)

        corporation_title = h(:th, th_props[corporation_props_size], ['Corporation ', render_toggle_not_floated_link])

        players_subtitles = []
        subtitles = []
        display_players.each_with_index do |p, idx|
          is_active_col = (p == active_player)
          props = { style: { backgroundColor: is_active_col ? COLOR_ACTIVE : 'inherit' } }

          props[:style][:width] = PLAYER_COL_MAX_WIDTH
          props[:style][:minWidth] = PLAYER_COL_MAX_WIDTH
          props[:style][:maxWidth] = PLAYER_COL_MAX_WIDTH
          props[:style][:position] = 'relative'
          props[:style][:overflow] = 'hidden'
          props[:style][:textOverflow] = 'ellipsis'
          props[:style][:textAlign] = 'left'
          props[:style][:paddingRight] = '22px'
          props[:style][:color] = '#000000'
          is_last = idx == @game.players.size - 1

          header_content = []
          header_content.concat(render_sort_link(p.name, p.id))

          if @game.respond_to?(:priority_deal_player) && p == @game.priority_deal_player
            header_content << h(:svg, {
                                  attrs: { viewBox: '0 0 16 16', width: '16', height: '16', title: 'Priority Deal' },
                                  style: {
                                    position: 'absolute',
                                    right: '4px',
                                    top: '50%',
                                    transform: 'translateY(-50%)',
                                    fill: COLOR_CASH,
                                  },
                                }, [
              h(:rect, attrs: { x: '0', y: '2', width: '6', height: '1' }),
              h(:rect, attrs: { x: '1', y: '3', width: '4', height: '7' }),
              h(:rect, attrs: { x: '11', y: '1', width: '2', height: '4' }),
              h(:rect, attrs: { x: '4', y: '5', width: '10', height: '5' }),
              h(:rect, attrs: { x: '1', y: '10', width: '14', height: '2' }),
              h(:polygon, attrs: { points: '14,10 16,12 14,12' }),
              h(:circle, attrs: { cx: '3.5', cy: '13.5', r: '1.5' }),
              h(:circle, attrs: { cx: '8.5', cy: '13.5', r: '1.5' }),
              h(:circle, attrs: { cx: '12.5', cy: '13.5', r: '1.5' }),
            ])
          end

          players_subtitles << h("th.name.nowrap#{'.thick-right' if is_last}", props, header_content)
        end

        pool_subtitles = [
          h('th.column-zone-market', { attrs: { class: 'column-zone-market' }, style: { color: '#000000' } },
            render_sort_link('Shares', :market_shares)),
          h('th.thick-right.column-zone-market', { attrs: { class: 'column-zone-market' }, style: { color: '#000000' } },
            render_sort_link('Price', :share_price)),
        ]
        ipo_subtitles = [
          h('th.column-zone-market', { attrs: { class: 'column-zone-market' }, style: { color: '#000000' } },
            render_sort_link('Shares', :ipo_shares)),
          h('th.thick-right.column-zone-market', { attrs: { class: 'column-zone-market' }, style: { color: '#000000' } },
            render_sort_link('Price', :par_price)),
        ]

        corporation_subtitles = [
h('th.column-zone-corporate', {}, render_sort_link('Cash', :cash)),
*treasury,
h('th.column-zone-corporate', {}, render_sort_link('Trains', :trains)),
h('th.column-zone-corporate', {}, render_sort_link('Tokens', :tokens)),
*extra,
        ]

        corporation_subtitles << h('th.column-zone-corporate', {}, render_sort_link('Privates', :companies)) if @show_privates
        corporation_subtitles << h('th.column-zone-corporate', {}, render_sort_link('Last Run', :prev_revenue))

        titles = [
          players_title,
          pool_title,
          ipo_title,
          corporation_title,
        ]
        subtitles.concat(players_subtitles)
        subtitles.concat(pool_subtitles)
        subtitles.concat(ipo_subtitles)
        subtitles.concat(corporation_subtitles)

        [
          h(:tr, [
            h('th.thick-right', { style: { minWidth: '5rem' } }, ''),
            *titles,
          ]),
          h(:tr, [
            h('th.thick-right', { style: { paddingBottom: '0.3rem' } }, ''),
            *subtitles,
          ]),
        ]
      end

      def render_sort_link(text, _sort_by)
        # Returns a simple flat text element array, decoupling the link layers and disabling sorting
        [text]
      end

      def sort_order_icon
        return '↓' if @spreadsheet_sort_order == 'ASC'

        '↑'
      end

      def mark_sort_column(sort_by)
        Lib::Storage['spreadsheet_sort_by'] = sort_by
        update
      end

      def toggle_sort_order
        Lib::Storage['spreadsheet_sort_order'] = @spreadsheet_sort_order == 'ASC' ? 'DESC' : 'ASC'
        update
      end

      def render_toggle_not_floated_link
        toggle = lambda do
          Lib::Storage['spreadsheet_hide_not_floated'] = !@hide_not_floated
          update
        end

        h('span.small_font', [
          '(',
          h(:a,
            {
              attrs: {
                onclick: 'return false',
                title: @hide_not_floated ? 'Show all corporations' : 'Hide not floated corporations',
              },
              on: { click: toggle },
              style: {
                cursor: 'pointer',
                textDecoration: 'underline',
              },
            },
            @hide_not_floated ? 'Show unfloated' : 'Hide unfloated'),
          ')',
        ])
      end

      def sorted_corporations
        operating_array =
          if @game.round.operating?
            @game.round.entities
          else
            @game.operating_order
          end
        operating_corporations = operating_array.each_with_index.to_h

        all_entities = @game.respond_to?(:minors) ? (@game.minors || []) : []
        all_entities += @game.all_corporations

        all_entities.reject! { |c| c.respond_to?(:closed?) && c.closed? }

        unfloated_corporations =
          (all_entities - operating_array)
            .select { |c| c.respond_to?(:sort_order_key) && c.sort_order_key }
            .sort
            .each_with_index.to_h

        result = all_entities.map do |c|
          operating_order =
            if (index = operating_corporations[c])
              [FLOATED, index + 1]
            elsif (index = unfloated_corporations[c])
              [UNFLOATED, index + 1]
            else
              [UNSTARTED, 0]
            end
          [operating_order, c]
        end

        result.sort_by! do |operating_order, corporation|
          is_minor = corporation.minor? ? 0 : 1
          minor_order = corporation.minor? ? operating_order[1] : 0
          major_status = corporation.minor? ? 0 : -operating_order[0]
          major_price = corporation.minor? ? 0 : -(corporation.share_price&.price || 0)
          major_secondary_order = corporation.minor? ? 0 : operating_order[1]

          [is_minor, minor_order, major_status, major_price, major_secondary_order]
        end

        result
      end

      def render_corporation(corporation, _operating_order, _current_round, is_last_minor = false)
        return '' if @hide_not_floated && !@game.operating_order.include?(corporation)

        step = @game.round.active_step
        is_active_row = (active_entity == corporation)

        is_unfloated = corporation.respond_to?(:floated?) && !corporation.floated?
        is_directed = corporation.respond_to?(:owner) && (corporation.owner == active_player)

        tr_props = tr_default_props(is_active_row)
        tr_props[:attrs] ||= {}

        # Attach DOM tracking and the FLIP animation hooks
        tr_props[:key] = corporation.id
        tr_props[:hook] = Lib::RowAnimation.hook(corporation.id)

        row_classes = []

        president_sold = corporation.respond_to?(:owner) && corporation.owner ? true : false
        president_available = if corporation.respond_to?(:minor?) && corporation.minor?
                                !president_sold
                              elsif corporation.respond_to?(:available?)
                                corporation.available?
                              elsif @game.respond_to?(:corporation_available?)
                                @game.corporation_available?(corporation)
                              else
                                true
                              end

        should_grey_unfloated = if @game.round.operating?
                                  is_unfloated
                                else
                                  is_unfloated && !(president_available || president_sold)
                                end

        row_classes << 'company-row-unfloated' if should_grey_unfloated
        row_classes << 'active-turn-focus' if is_active_row
        row_classes << 'directed-by-active-player' if is_directed && !is_active_row
        row_classes << 'last-minor-row' if is_last_minor

        tr_props[:attrs][:class] = row_classes.join(' ') unless row_classes.empty?

        is_operating = @game.operating_order.include?(corporation)
        is_open = corporation.respond_to?(:floated?) ? corporation.floated? : is_operating
        sold_more = if corporation.respond_to?(:percent_sold) && corporation.respond_to?(:float_percent)
                      corporation.percent_sold > corporation.float_percent
                    else
                      is_open
                    end
        is_mauve_corp = is_operating && is_open && sold_more
        corp_zone_bg = is_mauve_corp ? 'var(--bg-corporate-zone)' : COLOR_INACTIVE

        corp_bg_color = corporation.color
        if !is_operating && corp_bg_color == COLOR_MAUVE
          corp_bg_color = COLOR_INACTIVE
        elsif is_mauve_corp
          corp_bg_color = COLOR_MAUVE
        end
        name_props = {
          attrs: { class: 'status-corp-wrapper' },
          style: {
            backgroundColor: corporation.color,
            color: corporation.text_color,
            fontFamily: FONT_STD,
            fontWeight: 'bold',
            position: 'relative',
            cursor: 'help',
          },
        }

        # Map active corporate property cells
        treasury = []
        if @game.separate_treasury?
          num_sh = num_shares_of(corporation, corporation)
          content = if num_sh.positive?
                      pct = corporation.respond_to?(:share_percent) && corporation.share_percent ? (num_sh * corporation.share_percent) : (num_sh * 10)
                      [render_railcard("#{pct}%", ['game-card'])]
                    else
                      [h(:span, { style: { opacity: '0.35', fontSize: '0.8rem', fontFamily: 'var(--font-standard)' } }, '0%')]
                    end

          treasury << h('td.column-zone-corporate',
                        { style: { backgroundColor: corp_zone_bg, textAlign: 'center', minWidth: '3.5rem' } },
                        content)
        end

        extra = []
        if @game.respond_to?(:capitalization_type_desc)
          desc_text = @game.capitalization_type_desc(corporation)
          if @is_escrow_game && desc_text&.include?('Escrow')
            clean_digits = desc_text.scan(/\d+/).first || '0'
            extra << h('td.money-value', { style: { backgroundColor: corp_zone_bg } }, clean_digits)
          else
            extra << h('td', { style: { backgroundColor: corp_zone_bg } }, desc_text)
          end
        end

        extra << h('td', { style: { backgroundColor: corp_zone_bg } }, [render_loan_dots(corporation)]) if @game.total_loans&.nonzero?
        if @game.respond_to?(:available_shorts)
          taken, total = if @game.respond_to?(:available_shorts)
                           @game.available_shorts(corporation)
                         else
                           [0, 0]
                         end
          extra << h('td', { style: { backgroundColor: corp_zone_bg } }, "#{taken} / #{total}")
        end

        if @diff_corp_sizes
          size_name = if corporation.minor?
                        'Minor'
                      elsif @game.respond_to?(:corporation_size_name)
                        @game.corporation_size_name(corporation)
                      else
                        ''
                      end
          extra << h('td', { style: { backgroundColor: corp_zone_bg } }, size_name)
        end

        extra << h('td.column-zone-corporate', {}, [render_loan_dots(corporation)]) if @game.total_loans&.nonzero?
        if @game.respond_to?(:available_shorts)
          taken, total = if @game.respond_to?(:available_shorts)
                           @game.available_shorts(corporation)
                         else
                           [0, 0]
                         end
          extra << h('td.column-zone-corporate', {}, "#{taken} / #{total}")
        end

        if @diff_corp_sizes
          size_name = if corporation.minor?
                        'Minor'
                      elsif @game.respond_to?(:corporation_size_name)
                        @game.corporation_size_name(corporation)
                      else
                        ''
                      end
          extra << h('td.column-zone-corporate', {}, size_name)
        end

        n_ipo_shares = corporation.minor? ? 0 : num_ipo_shares(corporation)
        n_market_shares = num_shares_of(@game.share_pool, corporation)

        players_row_content = []

        display_players.each do |p|
          is_active_col = (p == active_player) && !is_active_row
          bg_color = is_active_col ? COLOR_ACTIVE : 'inherit'

          step = @game.round.active_step

          player_shares = p.respond_to?(:shares_of) ? p.shares_of(corporation) : []
          bundles = []

          active_step_actions = if step.respond_to?(:actions)
                                  begin
                                    step.actions(p) || []
                                  rescue StandardError
                                    []
                                  end
                                elsif step.respond_to?(:current_actions)
                                  step.current_actions || []
                                else
                                  []
                                end

          can_sell_now = (p == active_player) && active_step_actions.include?('sell_shares')

          if @game.round.operating?
            # In an Operating Round, selling is only permitted during an emergency train purchase / cash crisis
            emergency_active = if step.respond_to?(:can_sell_shares?)
                                 step.can_sell_shares?(p)
                               elsif step.respond_to?(:must_sell?)
                                 step.must_sell?(p)
                               elsif step.respond_to?(:must_buy_train?)
                                 step.must_buy_train?(active_entity)
                               elsif step.respond_to?(:cash_crisis?)
                                 step.cash_crisis?
                               elsif step.respond_to?(:emergency?)
                                 step.emergency?
                               else
                                 # Fallback to checking step class name or direct actions on active entity
                                 step.class.name.include?('BuyTrain') && active_step_actions.include?('sell_shares')
                               end
            can_sell_now = false unless emergency_active
          end

          if can_sell_now
            if step.respond_to?(:bundles_for_corporation)
              legal_bundles = step.bundles_for_corporation(p, corporation) || []
              legal_bundles.each do |b|
                next if step.respond_to?(:can_sell?) && !step.can_sell?(p, b)

                numeric_price = corporation.share_price ? corporation.share_price.price : 0
                bundles << { shares: b.shares, percent: b.percent, share_price: numeric_price, bundle: b }
              end
            elsif step.respond_to?(:can_sell?)
              sorted_shares = player_shares.sort_by { |s| s.respond_to?(:president) && s.president ? 1 : 0 }
              (1..sorted_shares.size).each do |num|
                chosen_shares = sorted_shares[0...num]
                b = begin
                  Engine::ShareBundle.new(chosen_shares)
                rescue StandardError
                  nil
                end
                next if b && !step.can_sell?(p, b)

                total_percent = chosen_shares.sum { |s| s.respond_to?(:percent) ? s.percent : 10 }
                numeric_price = corporation.share_price ? corporation.share_price.price : 0
                bundles << { shares: chosen_shares, percent: total_percent, share_price: numeric_price, bundle: b }
              end
            end
          end

          can_sell = (p == active_player) && !bundles.empty?

          # Check if the active player can buy from this specific player (e.g., Nationalization)
          valid_player_buys = []
          if !can_sell && p != active_player && step.respond_to?(:can_buy?)
            player_shares.each do |s|
              valid_player_buys << s if step.can_buy?(active_player, s.to_bundle)
            end
          end
          can_buy_from_player = !valid_player_buys.empty?
          click_handler = nil

          if can_sell
            click_handler = if bundles.size > 1
                              lambda {
                                Lib::Storage['sell_menu_player'] = p.id
                                Lib::Storage['sell_menu_corp'] = corporation.id
                                update
                              }
                            else
                              lambda { |_event|
                                source_selector = "#player_shares_#{p.id}_#{corporation.id} .game-card"
                                exec_sell_shares(source_selector, p, bundles.first, corporation.id)
                              }
                            end
          elsif can_buy_from_player
            click_handler = if valid_player_buys.uniq { |s| s.to_bundle.percent }.size > 1
                              lambda {
                                Lib::Storage['buy_player_menu_player'] = p.id
                                Lib::Storage['buy_player_menu_corp'] = corporation.id
                                update
                              }
                            else
                              lambda {
                                bnd = valid_player_buys.first.to_bundle
                                source_selector = "#player_shares_#{p.id}_#{corporation.id} .game-card"
                                exec_buy_shares(source_selector, active_player, bnd, corporation.id)
                              }
                            end
          end

          if corporation.minor?
            players_row_content << if corporation.owner == p
                                     card_classes = ['game-card']
                                     card_classes << 'action-sell' if can_sell
                                     card_classes << 'action-buy' if can_buy_from_player
                                     card_classes << 'clickable' if click_handler

                                     card_props = { attrs: { class: card_classes.join(' ') } }
                                     card_props[:on] = { click: click_handler } if click_handler

                                     h(:td, { style: { backgroundColor: bg_color, textAlign: 'center' } }, [
                                       h(:div, card_props, '100%'),
                                     ])
                                   else
                                     h(:td, { style: { backgroundColor: bg_color } }, '')
                                   end
          else
            n_shares = num_shares_of(p, corporation)

            just_sold = begin
              step&.did_sell?(corporation, p)
            rescue StandardError
              false
            end

            if n_shares.zero? && !can_buy_from_player && !just_sold
              players_row_content << h(:td,
                                       { attrs: { id: "player_shares_#{p.id}_#{corporation.id}" }, style: { backgroundColor: bg_color } }, '')
            else
              percent = p.percent_of(corporation) || (n_shares * 10)
              is_president = corporation.respond_to?(:president?) && corporation.president?(p)
              text = if n_shares.zero?
                       '0%'
                     else
                       "#{percent}%#{'P' if is_president}"
                     end

              card_classes = ['game-card']
              card_classes << 'action-sell' if can_sell
              card_classes << 'action-buy' if can_buy_from_player
              card_classes << 'clickable' if click_handler

              dropdowns = []

              if just_sold
                dropdowns << h(:span, {
                                 attrs: { class: 'token-bond' },
                                 style: {
                                   position: 'absolute',
                                   top: '10px',
                                   right: '-7px',
                                   width: '8px',
                                   height: '8px',
                                   borderRadius: '50%',
                                   backgroundColor: '#dc2626',
                                   visibility: 'visible',
                                 },
                               })
              end

              if Lib::Storage['sell_menu_player'] == p.id && Lib::Storage['sell_menu_corp'] == corporation.id && can_sell
                options = bundles.map do |bundle|
                  {
                    label: "#{bundle[:percent]}%",
                    action: lambda { |_event|
                      Lib::Storage['sell_menu_player'] = nil
                      Lib::Storage['sell_menu_corp'] = nil
                      source_selector = "#player_shares_#{p.id}_#{corporation.id} .game-card"
                      exec_sell_shares(source_selector, p, bundle, corporation.id)
                    },
                  }
                end

                cancel_handler = lambda {
                  Lib::Storage['sell_menu_player'] = nil
                  Lib::Storage['sell_menu_corp'] = nil
                  update
                }
                dropdowns << render_choice_menu('How many shares to sell?', options, cancel_handler)
              end

              if Lib::Storage['buy_player_menu_player'] == p.id && Lib::Storage['buy_player_menu_corp'] == corporation.id && can_buy_from_player
                options = valid_player_buys.map do |share|
                  {
                    label: "Buy #{share.to_bundle.percent}%",
                    action: lambda {
                      Lib::Storage['buy_player_menu_player'] = nil
                      Lib::Storage['buy_player_menu_corp'] = nil
                      source_selector = "#player_shares_#{p.id}_#{corporation.id} .game-card"
                      exec_buy_shares(source_selector, active_player, share.to_bundle, corporation.id)
                    },
                  }
                end

                cancel_handler = lambda {
                  Lib::Storage['buy_player_menu_player'] = nil
                  Lib::Storage['buy_player_menu_corp'] = nil
                  update
                }
                dropdowns << render_choice_menu('Nationalize share bundle?', options, cancel_handler)
              end

              card = render_railcard(text, card_classes, click_handler, nil, dropdowns)

              card = h(:span, { style: { visibility: 'hidden', display: 'inline-block' } }, [card]) if n_shares.zero?

              players_row_content << h(:td, { attrs: { id: "player_shares_#{p.id}_#{corporation.id}" }, style: { backgroundColor: bg_color, textAlign: 'center', position: 'relative' } },
                                       [card])
            end
          end
        end

        corp_actions = if is_active_row
                         actions = if @game.round.respond_to?(:actions_for)
                                     begin
                                       @game.round.actions_for(corporation)
                                     rescue StandardError
                                       []
                                     end
                                   else
                                     []
                                   end
                         actions = step.current_actions || [] if actions.empty? && step.respond_to?(:current_actions)
                         actions
                       else
                         []
                       end

        # --- Pool Shares Content (Redeem) ---
        can_redeem = false
        redeemable_bundles = []

        if is_active_row && ((%w[redeem_shares redeem corporate_buy_shares buy_shares] & corp_actions).any? || step.respond_to?(:redeemable_shares) || step.respond_to?(:redeemable_bundles))
          redeemable_bundles = begin
            if step.respond_to?(:redeemable_shares)
              begin
                step.redeemable_shares(corporation)
              rescue ArgumentError
                step.redeemable_shares
              end
            elsif step.respond_to?(:redeemable_bundles)
              begin
                step.redeemable_bundles(corporation)
              rescue ArgumentError
                step.redeemable_bundles
              end
            elsif @game.respond_to?(:redeemable_shares)
              @game.redeemable_shares(corporation)
            elsif (%w[redeem redeem_shares corporate_buy_shares] & corp_actions).any? && step.respond_to?(:buyable_shares)
              begin
                step.buyable_shares(corporation)
              rescue ArgumentError
                step.buyable_shares
              end
            else
              []
            end
          rescue StandardError
            []
          end || []

          redeemable_bundles = redeemable_bundles.map do |raw_b|
            raw_b.respond_to?(:to_bundle) && !raw_b.respond_to?(:num_shares) ? raw_b.to_bundle : raw_b
          end.select do |b|
            b_corp = if b.respond_to?(:corporation)
                       b.corporation
                     elsif b.respond_to?(:shares) && b.shares.first&.respond_to?(:corporation)
                       b.shares.first.corporation
                     end
            b_corp.nil? || b_corp == corporation
          end

          can_redeem = redeemable_bundles.any?
        end

        pool_share_text = if corporation.minor? || (n_market_shares.zero? && !can_redeem)
                            ''
                          else
                            is_receivership = corporation.respond_to?(:receivership?) && corporation.receivership?
                            pct = n_market_shares.positive? ? (n_market_shares * 10) : (redeemable_bundles.first&.percent || 10)
                            "#{'*' if is_receivership}#{pct}%"
                          end
        pool_click_handler = nil
        valid_pool_shares = []

        if can_redeem
          affordable_bundles = redeemable_bundles.select do |bundle|
            num = if bundle.respond_to?(:num_shares)
                    bundle.num_shares
                  else
                    (bundle.respond_to?(:shares) ? bundle.shares.size : 1)
                  end
            price = if bundle.respond_to?(:price)
                      bundle.price
                    elsif bundle.respond_to?(:share_price) && bundle.share_price
                      bundle.share_price.price * num
                    elsif corporation.respond_to?(:share_price) && corporation.share_price
                      corporation.share_price.price * num
                    else
                      0
                    end
            (corporation.respond_to?(:cash) ? corporation.cash : 0) >= price
          end

          if affordable_bundles.any?
            pool_click_handler = if affordable_bundles.size > 1
                                   lambda {
                                     Lib::Storage['redeem_menu_corp'] = corporation.id
                                     update
                                   }
                                 else
                                   lambda { |_event|
                                     exec_redeem_share_bundle(corporation, affordable_bundles.first, corp_actions)
                                   }
                                 end
          end
        elsif step.respond_to?(:can_buy?) && active_player
          pool_shares = step.respond_to?(:pool_shares) ? step.pool_shares(corporation) : (@game.share_pool.shares_by_corporation[corporation] || [])
          valid_pool_shares = pool_shares.select do |s|
            (s.respond_to?(:buyable) ? s.buyable : true) && step.can_buy?(active_player, s.to_bundle)
          end

          unless valid_pool_shares.empty?
            pool_click_handler = if valid_pool_shares.uniq { |s| s.to_bundle.percent }.size > 1
                                   lambda {
                                     Lib::Storage['buy_pool_menu_corp'] = corporation.id
                                     update
                                   }
                                 else
                                   lambda { |_event|
                                     source_selector = "#pool_shares_#{corporation.id} .game-card"
                                     exec_buy_shares(source_selector, active_player, valid_pool_shares.first.to_bundle, corporation.id)
                                   }
                                 end
          end
        end

        pool_cell_children = []
        unless pool_share_text.empty?
          card_classes = ['game-card']

          if can_redeem || pool_click_handler
            card_classes << 'action-buy'
            card_classes << 'clickable' if pool_click_handler
          end

          dropdowns = []
          if Lib::Storage['redeem_menu_corp'] == corporation.id && can_redeem && !redeemable_bundles.empty?
            options = redeemable_bundles.map do |bundle|
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
                      elsif corporation.respond_to?(:share_price) && corporation.share_price
                        corporation.share_price.price * num
                      else
                        0
                      end
              price_str = @game.format_currency(price)
              can_afford = (corporation.respond_to?(:cash) ? corporation.cash : 0) >= price
              {
                label: "Redeem #{pct_str} (#{price_str})",
                action: lambda { |_event|
                  return unless can_afford

                  Lib::Storage['redeem_menu_corp'] = nil
                  exec_redeem_share_bundle(corporation, bundle, corp_actions)
                },
              }
            end
            cancel_handler = lambda {
              Lib::Storage['redeem_menu_corp'] = nil
              update
            }
            dropdowns << render_choice_menu('Redeem from Pool:', options, cancel_handler)
          end

          if Lib::Storage['buy_pool_menu_corp'] == corporation.id && !valid_pool_shares.empty?
            options = valid_pool_shares.map do |share|
              {
                label: "Buy #{share.to_bundle.percent}%",
                action: lambda { |_event|
                  Lib::Storage['buy_pool_menu_corp'] = nil
                  source_selector = "#pool_shares_#{corporation.id} .game-card"
                  exec_buy_shares_simple(source_selector, active_player, share.to_bundle, corporation.id)
                },
              }
            end
            cancel_handler = lambda {
              Lib::Storage['buy_pool_menu_corp'] = nil
              update
            }
            dropdowns << render_choice_menu('Buy from Pool:', options, cancel_handler)
          end

          pool_cell_children << render_railcard(pool_share_text, card_classes, pool_click_handler, nil, dropdowns)
        end

        # --- Pool Market Price Content ---
        market_style = {}
        if corporation.share_price&.highlight? &&
          (m_color = StockMarket::COLOR_MAP[@game.class::STOCKMARKET_COLORS[corporation.share_price.type]])
          market_style[:backgroundColor] = m_color
          market_style[:color] = contrast_on(m_color)
        end
        is_operating = @game.operating_order.include?(corporation)
        clean_market_price = if corporation.share_price && is_operating
                               @game.format_currency(corporation.share_price.price)
                             else
                               ''
                             end

        pool_row_content = [
                  h('td.column-zone-market',
                    { attrs: { id: "pool_shares_#{corporation.id}" }, style: { position: 'relative', textAlign: 'center' } }, pool_cell_children),
                  h('td.padded_number.column-zone-market.money-value', { style: market_style }, clean_market_price),
                ]

        # --- IPO Shares Content ---
        issuable_bundles = []
        if is_active_row && ((%w[issue_shares reissue_shares reissue corporate_sell_shares sell_shares] & corp_actions).any? || step.respond_to?(:issuable_shares) || step.respond_to?(:issuable_bundles))
          issuable_bundles = begin
            if step.respond_to?(:issuable_shares)
              begin
                step.issuable_shares(corporation)
              rescue ArgumentError
                step.issuable_shares
              end
            elsif step.respond_to?(:issuable_bundles)
              begin
                step.issuable_bundles(corporation)
              rescue ArgumentError
                step.issuable_bundles
              end
            elsif @game.respond_to?(:issuable_shares)
              @game.issuable_shares(corporation)
            elsif step.respond_to?(:bundles_for_corporation)
              begin
                step.bundles_for_corporation(corporation, corporation)
              rescue ArgumentError
                step.bundles_for_corporation(corporation)
              end
            elsif step.respond_to?(:bundles)
              step.bundles(corporation)
            else
              []
            end
          rescue StandardError
            []
          end || []
        end
        can_issue = is_active_row && issuable_bundles.any?

        ipo_share_text = if n_ipo_shares.positive?
                           "#{n_ipo_shares * 10}%"
                         elsif can_issue && issuable_bundles.any?
                           pct = issuable_bundles.first.respond_to?(:percent) ? issuable_bundles.first.percent : 10
                           "#{pct}%"
                         else
                           ''
                         end
        ipo_click_handler = nil
        valid_ipo_shares = []

        if can_issue
          ipo_click_handler = if issuable_bundles.size > 1
                                lambda {
                                  Lib::Storage['issue_menu_corp'] = corporation.id
                                  update
                                }
                              else
                                lambda { |_event|
                                  exec_issue_share_bundle(corporation, issuable_bundles.first, corp_actions)
                                }
                              end
        else
          player_actions = if active_player && @game.round.respond_to?(:actions_for)
                             begin
                               @game.round.actions_for(active_player)
                             rescue StandardError
                               []
                             end
                           elsif step.respond_to?(:actions)
                             begin
                               step.actions(active_player) || []
                             rescue StandardError
                               []
                             end
                           elsif step.respond_to?(:current_actions)
                             step.current_actions || []
                           else
                             []
                           end || []
          is_corp = corporation.respond_to?(:corporation?) &&
                     corporation.corporation? &&
                     (!corporation.respond_to?(:minor?) || !corporation.minor?) &&
                     (!corporation.respond_to?(:ipoed) || !corporation.ipoed)

          corp_available = if corporation.respond_to?(:available?)
                             corporation.available?
                           elsif @game.respond_to?(:corporation_available?)
                             @game.corporation_available?(corporation)
                           else
                             true
                           end

          can_par = is_corp &&
                     active_player &&
                     player_actions.include?('par') &&
                     corp_available &&
                     (!@game.respond_to?(:can_par?) || @game.can_par?(corporation, active_player)) &&
                     (!step.respond_to?(:can_par?) || begin
                       step.can_par?(corporation, active_player)
                     rescue ArgumentError
                       step.can_par?(active_player, corporation)
                     end)

          can_bid = active_player && player_actions.include?('bid') && (
            if step.respond_to?(:can_bid?)
              begin
                step.can_bid?(active_player, corporation)
              rescue ArgumentError
                step.can_bid?(corporation)
              end
            elsif is_corp && @game.respond_to?(:can_par?)
              @game.can_par?(corporation, active_player)
            else
              corporation.respond_to?(:ipoed) ? !corporation.ipoed : true
            end
          )

          par_prices = []
          if can_par
            par_prices = if step.respond_to?(:get_par_prices_with_help)
                           step.get_par_prices_with_help(active_player, corporation).sort_by(&:price)
                         elsif step.respond_to?(:get_par_prices)
                           step.get_par_prices(active_player, corporation).sort_by(&:price)
                         elsif @game.respond_to?(:par_prices)
                           @game.par_prices(corporation).sort_by(&:price)
                         else
                           @game.stock_market.par_prices.sort_by(&:price)
                         end
            if @game.respond_to?(:par_chart)
              par_prices = par_prices.reject do |sp|
                slots = @game.par_chart[sp]
                slots && slots.none?(&:nil?)
              end
            end

            # Resolve presidency certificate share multiplier
            pres_share = if corporation.respond_to?(:presidents_share) && corporation.presidents_share
                           corporation.presidents_share
                         elsif corporation.respond_to?(:shares) && corporation.shares&.first
                           corporation.shares.first
                         end

            shares_multiplier = if pres_share.respond_to?(:multiplier) && pres_share.multiplier
                                  pres_share.multiplier
                                elsif pres_share.respond_to?(:percent) && corporation.respond_to?(:share_percent) && corporation.share_percent&.positive?
                                  (pres_share.percent / corporation.share_percent).to_i
                                elsif pres_share.respond_to?(:percent)
                                  (pres_share.percent / 10).to_i
                                else
                                  2
                                end

            if step.respond_to?(:par_shares)
              bundle = begin
                step.par_shares(corporation)
              rescue ArgumentError
                step.par_shares(active_player, corporation)
              end
              if bundle
                shares_multiplier = if bundle.respond_to?(:num_shares)
                                      bundle.num_shares
                                    elsif bundle.respond_to?(:shares) && bundle.shares
                                      bundle.shares.size
                                    else
                                      shares_multiplier
                                    end
              end
            end
            shares_multiplier = 1 if shares_multiplier.to_i <= 0

            # Filter prices strictly to what the active player can physically afford
            player_cash = active_player.respond_to?(:cash) ? (active_player.cash || 0) : 0
            par_prices = par_prices.select do |sp|
              price_val = sp.respond_to?(:price) ? sp.price : sp.to_i
              player_cash >= (price_val * shares_multiplier)
            end

            unless par_prices.empty?
              ipo_click_handler = lambda {
                Lib::Storage['par_menu_corp'] = corporation.id
                update
              }
            end
          elsif can_bid
            ipo_click_handler = lambda {
              store(:selected_corporation, corporation)
              store(:selected_company, corporation)
              Lib::Storage['selected_bid_corp'] = corporation.id
              update
            }
          elsif step.respond_to?(:can_buy?) && active_player
            ipo_shares = corporation.respond_to?(:ipo_shares) ? corporation.ipo_shares : []
            valid_ipo_shares = ipo_shares.select do |s|
              (s.respond_to?(:buyable) ? s.buyable : true) && step.can_buy?(active_player, s.to_bundle)
            end

            unless valid_ipo_shares.empty?
              ipo_click_handler = if valid_ipo_shares.uniq { |s| s.to_bundle.percent }.size > 1
                                    lambda {
                                      Lib::Storage['buy_ipo_menu_corp'] = corporation.id
                                      update
                                    }
                                  else
                                    lambda { |_event|
                                      source_selector = "#ipo_shares_#{corporation.id} .game-card"
                                      exec_buy_shares(source_selector, active_player, valid_ipo_shares.first.to_bundle, corporation.id)
                                    }
                                  end
            end
          end
        end

        ipo_cell_children = []
        unless ipo_share_text.empty?
          card_classes = ['game-card']
          if can_issue
            card_classes << 'action-sell'
            card_classes << 'clickable' if ipo_click_handler
          elsif ipo_click_handler
            card_classes << 'action-buy'
            card_classes << 'clickable'
          end

          dropdowns = []

          if Lib::Storage['issue_menu_corp'] == corporation.id && can_issue && !issuable_bundles.empty?
            options = issuable_bundles.map do |bundle|
              num = if bundle.respond_to?(:num_shares)
                      bundle.num_shares
                    else
                      (bundle.respond_to?(:shares) ? bundle.shares.size : 1)
                    end
              pct_str = bundle.respond_to?(:percent) && bundle.percent ? "#{bundle.percent}%" : "#{num}S"
              {
                label: "Issue #{pct_str}",
                action: lambda { |_event|
                  Lib::Storage['issue_menu_corp'] = nil
                  exec_issue_share_bundle(corporation, bundle, corp_actions)
                },
              }
            end
            cancel_handler = lambda {
              Lib::Storage['issue_menu_corp'] = nil
              update
            }
            dropdowns << render_choice_menu('Issue shares:', options, cancel_handler)
          end

          if Lib::Storage['buy_ipo_menu_corp'] == corporation.id && !valid_ipo_shares.empty?
            options = valid_ipo_shares.map do |share|
              {
                label: "Buy #{share.to_bundle.percent}%",
                action: lambda { |_event|
                          Lib::Storage['buy_ipo_menu_corp'] = nil
                          source_selector = "#ipo_shares_#{corporation.id} .game-card"
                          exec_buy_shares_simple(source_selector, active_player, share.to_bundle, corporation.id)
                        },
              }
            end
            cancel_handler = lambda {
              Lib::Storage['buy_ipo_menu_corp'] = nil
              update
            }
            dropdowns << render_choice_menu('Buy from IPO:', options, cancel_handler)
          end

          ipo_cell_children << render_railcard(ipo_share_text, card_classes, ipo_click_handler, nil, dropdowns)
        end

        # --- IPO Par Price Content ---
        clean_par_price = corporation.par_price ? @game.format_currency(corporation.par_price.price) : ''
        ipo_row_content = [
                  h('td.column-zone-market', { attrs: { id: "ipo_shares_#{corporation.id}" }, style: { position: 'relative', textAlign: 'center' } },
                    ipo_cell_children),
                  h('td.padded_number.column-zone-market.money-value', {}, clean_par_price),
                ]

        train_buyable_step = step&.current_actions&.include?('buy_train')
        train_discardable_step = step&.current_actions&.include?('discard_train')
        step_buyable_trains = if train_buyable_step && active_entity && step.respond_to?(:buyable_trains)
                                step.buyable_trains(active_entity)
                              end
        corp_owner = lambda do |corp|
          step.respond_to?(:corp_owner) ? step.corp_owner(corp) : corp&.owner
        end
        same_player = active_entity && corporation != active_entity &&
                      corp_owner.call(corporation) &&
                      corp_owner.call(corporation) == corp_owner.call(active_entity)

        train_cards = corporation.trains.map do |t|
          card_classes = ['game-card']
          train_click_handler = nil
          menu_dropdown = nil

          # Check if the train is authoritatively buyable by active_entity (strictly from same player)
          is_buyable_other_train = if !same_player
                                     false
                                   elsif step_buyable_trains
                                     step_buyable_trains.include?(t)
                                   elsif train_buyable_step
                                     !step.respond_to?(:can_buy_train?) || step.can_buy_train?(active_entity, t)
                                   else
                                     false
                                   end

          if is_buyable_other_train
            card_classes << 'action-buy'
            card_classes << 'clickable'

            min_price = 1
            max_price = if step.respond_to?(:max_price)
                          step.max_price(active_entity, t)
                        else
                          (active_entity.respond_to?(:cash) ? active_entity.cash : 9999)
                        end

            train_click_handler = lambda {
              `var p = document.getElementById('railcard-portal'); if (p) { p.style.display = 'none'; p.innerHTML = ''; }`
              menu_title = "Buy #{t.name} from #{corporation.name} (#{min_price}-#{max_price}):"
              default_price = min_price

              show_price_dialog(
                menu_title,
                min_price,
                max_price,
                default_price,
                lambda { |price_val|
                  escaped_train_wrapper_id = `CSS.escape('train_wrapper_' + #{corporation.id} + '_' + #{t.id})`
                  source_selector = "##{escaped_train_wrapper_id} .game-card"
                  exec_buy_corporate_train(source_selector, active_entity, t, price_val)
                }
              )
            }

          elsif train_discardable_step && active_entity == corporation
            card_classes << 'action-sell'
            card_classes << 'clickable'

            train_click_handler = lambda {
              escaped_train_wrapper_id = `CSS.escape('train_wrapper_' + #{corporation.id} + '_' + #{t.id})`
              source_selector = "##{escaped_train_wrapper_id} .game-card"
              target_selector = '#extra_cards'
              Lib::CardAnimation.fly(source_selector, target_selector) do
                process_action(Engine::Action::DiscardTrain.new(
                  active_entity,
                  train: t
                ))
              end
            }
          end

          wrapper_id = "train_wrapper_#{corporation.id}_#{t.id}"
          render_railcard(t.obsolete ? "(#{t.name})" : t.name, card_classes, train_click_handler, nil, menu_dropdown, wrapper_id)
        end

        limit = begin
          @game.train_limit(corporation)
        rescue StandardError
          corporation.trains.size
        end
        limit = corporation.trains.size if limit < corporation.trains.size

        empty_count = [limit - corporation.trains.size, 0].max
        empty_count.times do
          train_cards << h(:div, {
                             style: {
                               width: '3.5rem',
                               height: '1.45rem',
                               backgroundColor: 'transparent',
                               border: '1px dashed #999',
                               borderRadius: '4px',
                               margin: '2px',
                               boxSizing: 'border-box',
                               display: 'inline-flex',
                               verticalAlign: 'middle',
                             },
                           })
        end

        clean_corp_cash = @game.format_currency(corporation.cash)

        last_rev = corporation.operating_history.values.last&.revenue
        clean_rev = last_rev ? @game.format_currency(last_rev) : ''

        corporation_row_content = [
                 h('td.padded_number.money-value',
                   { hook: Lib::MoneyAnimation.hook, style: { backgroundColor: corp_zone_bg } }, clean_corp_cash),
                 *treasury,
                 h('td',
                   { attrs: { id: "trains_#{corporation.id}" }, style: { backgroundColor: corp_zone_bg } }, train_cards),
                 h('td', { style: { backgroundColor: corp_zone_bg } }, [render_unplaced_tokens(corporation)]),
                 *extra,
                ]
        corporation_row_content << render_companies(corporation, corp_zone_bg) if @show_privates
        last_run = corporation.operating_history.values.last
        div = last_run.respond_to?(:dividend) ? last_run.dividend : (last_run[:dividend] if last_run.is_a?(Hash))
        div_kind = (div.respond_to?(:kind) ? div.kind : div).to_s.downcase

        held = if last_run.respond_to?(:withheld?)
                 last_run.withheld?
               elsif last_run.respond_to?(:withhold?)
                 last_run.withhold?
               else
                 div_kind.start_with?('withhold', 'held', 'hold')
               end

        half_held = if last_run.respond_to?(:half?)
                      last_run.half?
                    else
                      div_kind.start_with?('half', 'split')
                    end

        held = false if clean_rev.empty?
        half_held = false if clean_rev.empty? || held

        font_color = if held
                       '#dc2626' # Red
                     elsif half_held
                       '#d97706' # Amber / Orange
                     end

        rev_class = "td.padded_number#{font_color ? '' : '.money-value'}"
        rev_props = { hook: Lib::MoneyAnimation.hook }
        rev_props[:style] = { backgroundColor: corp_zone_bg, color: font_color, fontFamily: 'var(--font-money)', fontWeight: 'bold', fontVariantNumeric: 'tabular-nums' }.compact

        corporation_row_content << h(rev_class, rev_props, clean_rev)
        row_content = []
        row_content.concat(players_row_content)
        row_content.concat(pool_row_content)
        row_content.concat(ipo_row_content)
        row_content.concat(corporation_row_content)

        h(:tr, tr_props, [
          h(:th, name_props, [render_corp_tooltip(corporation), corporation.name].compact),
          *row_content,
        ])
      end

      def render_unplaced_tokens(corporation)
        return h(:span, '') unless corporation.respond_to?(:tokens)

        unplaced = corporation.tokens.select do |t|
          has_hex = t.respond_to?(:hex) && t.hex
          is_placed = t.respond_to?(:placed?) && t.placed?
          !has_hex && !is_placed
        end

        return h(:span, '') if unplaced.empty?

        logo_src = begin
          setting_for(:simple_logos, @game) ? corporation.simple_logo : corporation.logo
        rescue StandardError
          nil
        end

        tooltip_style = <<~CSS
          .unplaced-token-wrapper { position: relative; display: inline-flex; align-items: center; justify-content: center; cursor: help; margin: 2px; }
          .unplaced-token-wrapper[title]:not([title=""]):hover::after {
            content: attr(title);
            position: absolute;
            bottom: calc(100% + 4px);
            left: 50%;
            transform: translateX(-50%);
            background: rgba(15, 23, 42, 0.95);
            color: #ffffff;
            font-family: var(--font-money, monospace);
            font-size: 1.44rem;
            font-weight: bold;
            line-height: 1;
            padding: 4px 10px;
            border-radius: 5px;
            white-space: nowrap;
            pointer-events: none;
            z-index: 99999;
            box-shadow: 0 3px 6px rgba(0,0,0,0.35);
          }
        CSS

        token_icons = unplaced.map do |token|
          raw_cost = if token.respond_to?(:price) && !token.price.nil?
                       token.price
                     elsif token.respond_to?(:cost) && !token.cost.nil?
                       token.cost
                     elsif token.instance_variable_defined?(:@price) && !token.instance_variable_get(:@price).nil?
                       token.instance_variable_get(:@price)
                     elsif corporation.respond_to?(:token_price)
                       begin; corporation.token_price(token); rescue StandardError; nil; end
                     elsif @game.respond_to?(:token_cost)
                       begin; @game.token_cost(token); rescue StandardError; nil; end
                     end

          cost = raw_cost ? raw_cost.to_s : ''
          wrapper_props = {
            attrs: { class: 'unplaced-token-wrapper', title: cost },
          }

          if logo_src
            img_style = {
              width: '20px',
              height: '20px',
              borderRadius: '50%',
              boxSizing: 'border-box',
              display: 'block',
              border: '1px solid #333',
              backgroundColor: corporation.color || '#fff',
              pointerEvents: 'none',
            }
            h(:div, wrapper_props, [h(:img, { attrs: { src: logo_src }, style: img_style })])
          else
            div_style = {
              width: '20px',
              height: '20px',
              borderRadius: '50%',
              boxSizing: 'border-box',
              display: 'block',
              border: '1px solid #333',
              lineHeight: '18px',
              textAlign: 'center',
              backgroundColor: corporation.color || '#4169e1',
              color: corporation.text_color || '#fff',
              fontSize: '0.55rem',
              fontWeight: 'bold',
              pointerEvents: 'none',
            }
            h(:div, wrapper_props, [h(:div, { style: div_style }, corporation.id.to_s[0..2])])
          end
        end

        h(:div, { style: { display: 'flex', flexDirection: 'row', justifyContent: 'center', flexWrap: 'wrap' } },
          [h(:style, tooltip_style), *token_icons])
      end

      def render_corp_tokens(corporation)
        return h(:span, '') unless corporation.respond_to?(:tokens)

        tokens = corporation.tokens
        return h(:span, '') if tokens.empty?

        logo_src = begin
          setting_for(:simple_logos, @game) ? corporation.simple_logo : corporation.logo
        rescue StandardError
          nil
        end

        token_icons = tokens.map do |token|
          is_placed = token.respond_to?(:hex) && token.hex

          style = {
            width: '20px',
            height: '20px',
            margin: '2px',
            borderRadius: '50%',
            boxSizing: 'border-box',
            display: 'inline-block',
            border: '1px solid #333',
            opacity: is_placed ? '1' : '0.3',
          }

          if logo_src
            style[:backgroundColor] = corporation.color || '#fff'
            h(:img, { attrs: { src: logo_src }, style: style })
          else
            style[:lineHeight] = '18px'
            style[:textAlign] = 'center'
            style[:backgroundColor] = corporation.color || '#4169e1'
            style[:color] = corporation.text_color || '#fff'
            style[:fontSize] = '0.55rem'
            style[:fontWeight] = 'bold'
            h(:div, { style: style }, corporation.id.to_s[0..2])
          end
        end

        h(:div, { style: { display: 'flex', flexDirection: 'row', justifyContent: 'center', flexWrap: 'wrap' } }, token_icons)
      end

      def render_loan_dots(entity)
        return h(:div, '') if !entity.respond_to?(:loans) || !@game.respond_to?(:maximum_loans)

        loans_taken = entity.loans.size
        max_loans = @game.maximum_loans(entity)
        interest_owed = @game.respond_to?(:interest_owed) ? @game.interest_owed(entity) : 0

        dots = []
        loans_taken.times do
          dots << h(:span,
                    {
                      style: {
                        display: 'inline-block',
                        width: '8px',
                        height: '8px',
                        backgroundColor: '#dc3545',
                        borderRadius: '50%',
                        margin: '0 2px',
                        verticalAlign: 'middle',
                      },
                    })
        end
        [max_loans - loans_taken, 0].max.times do
          dots << h(:span,
                    {
                      style: {
                        display: 'inline-block',
                        width: '8px',
                        height: '8px',
                        border: '1px solid #dc3545',
                        borderRadius: '50%',
                        margin: '0 2px',
                        verticalAlign: 'middle',
                        boxSizing: 'border-box',
                      },
                    })
        end

        dots << h(:span, { style: { marginLeft: '4px', fontSize: '0.75rem', fontWeight: 'bold', verticalAlign: 'middle' } },
                  "(#{interest_owed})")

        h(:div, { style: { display: 'flex', alignItems: 'center', justifyContent: 'center' } }, dots)
      end

      def render_companies(entity, bg_color = nil)
        props = { attrs: { id: "companies_#{entity.id}", class: 'align-top' } }
        props[:style] = if entity.player?
                          {
                            maxWidth: PLAYER_COL_MAX_WIDTH,
                            whiteSpace: 'normal',
                            textAlign: 'right',
                            minWidth: min_width(entity),
                          }
                        else
                          {}
                        end
        props[:style][:backgroundColor] = bg_color if bg_color

        companies_list = entity.respond_to?(:companies) ? entity.companies : []
        companies_list = companies_list.reject { |c| c.respond_to?(:closed?) && c.closed? }

        step = @game.round.active_step
        active_ent = active_entity

        actions = if active_ent && @game.round.respond_to?(:actions_for)
                    @game.round.actions_for(active_ent)
                  else
                    step&.current_actions || []
                  end

        company_buyable_step = actions.include?('buy_company')

        special_actions = actions - %w[lay_tile place_token run_routes dividend payout withhold half split buy_train pass
                                       buy_company merge choose end_game bankrupt]
        valid_special_actions = special_actions.map do |action_name|
          action_class = begin
            Engine::Action.const_get(action_name.split('_').map(&:capitalize).join)
          rescue NameError
            nil
          end
          next nil unless action_class

          required_args = action_class.const_defined?(:REQUIRED_ARGS) ? action_class::REQUIRED_ARGS : []
          required_args.include?(:company) ? [action_name, action_class] : nil
        end.compact

        company_cards = companies_list.map do |c|
          card_classes = ['game-card']
          company_click_handler = nil
          menu_dropdown = nil

          not_own_company = active_ent && entity != active_ent

          buy_company_step = nil
          is_buyable = false

          if @game.round.respond_to?(:steps)
            buy_company_step = @game.round.steps.find do |s|
              (s.respond_to?(:buyable_companies) && s.buyable_companies(active_ent).include?(c)) ||
                (s.respond_to?(:can_buy_company?) && s.can_buy_company?(active_ent, c))
            end
            is_buyable = true if buy_company_step
          end

          unless is_buyable
            buy_company_step = step
            is_buyable = if step.respond_to?(:buyable_companies)
                           step.buyable_companies(active_ent).include?(c)
                         elsif step.respond_to?(:can_buy_company?)
                           step.can_buy_company?(active_ent, c)
                         elsif c.respond_to?(:owned_by?)
                           !c.owned_by?(active_ent)
                         else
                           c.owner != active_ent
                         end
          end

          # Restrict buyable list to only show privates owned by the operating corporation's president
          if active_ent.respond_to?(:corporation?) && active_ent.corporation? && (!c.owner || c.owner != active_ent.owner)
            is_buyable = false
          end

          matching_special_action = valid_special_actions.find do |_, _action_class|
            targets = if step.respond_to?(:available_targets)
                        step.available_targets(active_ent) || []
                      elsif step.respond_to?(:companies)
                        step.companies || []
                      else
                        []
                      end
            targets.include?(c)
          end

          if matching_special_action
            card_classes << 'action-buy'
            card_classes << 'clickable'
            company_click_handler = lambda {
              source_selector = "#company_wrapper_#{entity.id}_#{c.id} .game-card"
              target_selector = "#companies_#{active_ent.id}"
              Lib::CardAnimation.fly(source_selector, target_selector) do
                process_action(matching_special_action[1].new(active_ent, company: c))
              end
            }

          elsif company_buyable_step && not_own_company && is_buyable
            card_classes << 'action-buy'
            card_classes << 'clickable'

            min_price = if buy_company_step.respond_to?(:min_price)
                          buy_company_step.min_price(c)
                        else
                          (c.respond_to?(:min_price) ? c.min_price : 1)
                        end
            max_price = if buy_company_step.respond_to?(:max_price)
                          buy_company_step.max_price(active_ent, c)
                        else
                          (if c.respond_to?(:max_price)
                             c.max_price
                           else
                             (active_ent.respond_to?(:cash) ? active_ent.cash : 9999)
                           end)
                        end

            company_click_handler = lambda {
              `var p = document.getElementById('railcard-portal'); if (p) { p.style.display = 'none'; p.innerHTML = ''; }`
              menu_title = "Buy #{c.name} (#{min_price}-#{max_price}):"
              default_price = [active_ent.respond_to?(:cash) ? active_ent.cash : min_price, max_price].min
              default_price = [default_price, min_price].max

              show_price_dialog(
                menu_title,
                min_price,
                max_price,
                default_price,
                lambda { |price_val|
                  process_action(Engine::Action::BuyCompany.new(
                    active_ent,
                    company: c,
                    price: price_val
                  ))
                }
              )
            }
          end

          tooltip_card = build_company_tooltip(c)
          wrapper_id = "company_wrapper_#{entity.id}_#{c.id}"
          wrapper_classes = ['status-company-wrapper']

          render_railcard(c.sym, card_classes, company_click_handler, tooltip_card, menu_dropdown, wrapper_id, wrapper_classes)
        end
        h(:td, props, company_cards)
      end

      def render_player_companies
        h(:tr, tr_default_props, [
           h('th.left', 'Companies'),
           *display_players.map.with_index do |p, idx|
             is_active_col = (p == active_player)
             bg_color = is_active_col ? COLOR_ACTIVE : COLOR_INACTIVE
             is_last = idx == @game.players.size - 1
             h("td.align-top#{'.thick-right' if is_last}", { style: { backgroundColor: bg_color } }, [render_companies(p)])
           end,
           h(:td, { attrs: { colspan: 30 }, style: { border: 'none' } }, ''),
         ])
      end

      def exec_issue_share_bundle(corporation, bundle, corp_actions = nil)
        actions = corp_actions || (if @game.round.respond_to?(:actions_for)
                                     begin
                                       @game.round.actions_for(corporation)
                                     rescue StandardError
                                       []
                                     end
                                   else
                                     []
                                   end) || []
        sh_price = bundle.respond_to?(:share_price) ? bundle.share_price : corporation.share_price
        shares_arr = bundle.respond_to?(:shares) ? bundle.shares : [bundle]
        pct = bundle.respond_to?(:percent) ? bundle.percent : 10

        if actions.include?('issue_shares')
          process_action(Engine::Action::IssueShares.new(corporation, bundle: bundle))
        elsif actions.include?('reissue_shares') && defined?(Engine::Action::ReissueShares)
          process_action(Engine::Action::ReissueShares.new(corporation, bundle: bundle))
        elsif actions.include?('reissue') && defined?(Engine::Action::Reissue)
          process_action(Engine::Action::Reissue.new(corporation, bundle: bundle))
        elsif actions.include?('corporate_sell_shares')
          process_action(Engine::Action::CorporateSellShares.new(corporation, bundle: bundle))
        else
          process_action(Engine::Action::SellShares.new(corporation, shares: shares_arr, share_price: sh_price, percent: pct))
        end
      end

      def exec_redeem_share_bundle(corporation, bundle, corp_actions = nil)
        actions = corp_actions || (if @game.round.respond_to?(:actions_for)
                                     begin
                                       @game.round.actions_for(corporation)
                                     rescue StandardError
                                       []
                                     end
                                   else
                                     []
                                   end) || []
        num = if bundle.respond_to?(:num_shares)
                bundle.num_shares
              else
                (bundle.respond_to?(:shares) ? bundle.shares.size : 1)
              end
        sh_price = bundle.respond_to?(:share_price) && bundle.share_price ? bundle.share_price : corporation.share_price
        shares_arr = bundle.respond_to?(:shares) ? bundle.shares : [bundle]
        pct = bundle.respond_to?(:percent) ? bundle.percent : (num * 10)

        if actions.include?('redeem_shares')
          process_action(Engine::Action::RedeemShares.new(corporation, bundle: bundle))
        elsif actions.include?('redeem') && defined?(Engine::Action::Redeem)
          process_action(Engine::Action::Redeem.new(corporation, bundle: bundle))
        elsif actions.include?('corporate_buy_shares')
          process_action(Engine::Action::CorporateBuyShares.new(corporation, shares: shares_arr, share_price: sh_price, percent: pct))
        else
          process_action(Engine::Action::BuyShares.new(corporation, shares: shares_arr, share_price: sh_price, percent: pct))
        end
      end

      def render_player_cash
        h(:tr, tr_default_props, [
          h('th.left', 'Cash'),
          *display_players.map do |p|
            clean_cash = @game.format_currency(p.cash)
            is_active_col = (p == active_player)
            bg_color = is_active_col ? COLOR_ACTIVE : COLOR_INACTIVE

            h('td.padded_number.money-value',
              { hook: Lib::MoneyAnimation.hook, style: { backgroundColor: bg_color } }, clean_cash)
          end,
        ])
      end

      def render_player_certs
        cert_limit = @game.cert_limit
        props = { style: { color: 'red' } }
        h(:tr, tr_default_props, [
    h('th.left', 'Cert'),
    *display_players.map.with_index do |player, idx|
      is_active_col = (player == active_player)
      bg_color = is_active_col ? COLOR_ACTIVE : COLOR_INACTIVE
      num_certs = @game.num_certs(player)
      cell_props = num_certs > cert_limit ? props.merge(style: { backgroundColor: bg_color }) : { style: { backgroundColor: bg_color } }
      is_last = idx == @game.players.size - 1
      h("td.padded_number#{'.thick-right' if is_last}", cell_props, "#{num_certs}/#{cert_limit}")
    end,
    h(:td, { attrs: { colspan: 30 }, style: { border: 'none' } }, ''),
  ])
      end

      def render_player_loans
        return '' unless @game.respond_to?(:player_loans)

        h(:tr, tr_default_props, [
         h('th.left', 'Loans'),
         *display_players.map.with_index do |p, idx|
           is_active_col = (p == active_player)
           bg_color = is_active_col ? COLOR_ACTIVE : COLOR_INACTIVE
           is_last = idx == @game.players.size - 1
           h("td.padded_number#{'.thick-right' if is_last}", { style: { backgroundColor: bg_color } }, @game.player_loans(p))
         end,
         h(:td, { attrs: { colspan: 30 }, style: { border: 'none' } }, ''),
       ])
      end

      def tr_default_props(is_active_row = false)
        {
          style: {
            backgroundColor: is_active_row ? COLOR_ACTIVE : COLOR_INACTIVE,
            color: '#000000',
            fontFamily: FONT_STD,
          },
        }
      end

      def money_props(extra_style = {})
        { style: { fontFamily: FONT_MONEY, fontWeight: 'bold' }.merge(extra_style) }
      end

      def table_props
        {
          style: {
            borderCollapse: 'collapse',
            textAlign: 'center',
            whiteSpace: 'nowrap',
          },
        }
      end

      def exec_sell_shares(source_selector, player, target_bundle, corporation_id)
        escaped_corp_id = `CSS.escape(#{corporation_id})`
        Lib::CardAnimation.fly(source_selector, "#pool_shares_#{escaped_corp_id}") do
          process_action(Engine::Action::SellShares.new(
            player,
            shares: target_bundle[:shares],
            share_price: target_bundle[:share_price],
            percent: target_bundle[:percent]
          ))
        end
      end

      def exec_buy_shares(source_selector, player, bnd, corporation_id)
        escaped_player_id = `CSS.escape(#{player.id})`
        escaped_corp_id = `CSS.escape(#{corporation_id})`
        Lib::CardAnimation.fly(source_selector, "#player_shares_#{escaped_player_id}_#{escaped_corp_id}") do
          process_action(Engine::Action::BuyShares.new(
            player,
            shares: bnd.shares,
            share_price: bnd.share_price,
            percent: bnd.percent
          ))
        end
      end

      def exec_buy_shares_simple(source_selector, player, bnd, corporation_id)
        Lib::CardAnimation.fly(source_selector, "#player_shares_#{player.id}_#{corporation_id}") do
          process_action(Engine::Action::BuyShares.new(
            player,
            shares: bnd.shares,
            share_price: bnd.share_price,
            percent: bnd.percent
          ))
        end
      end

      def exec_buy_corporate_train(source_selector, active_entity, train, price_value)
        escaped_dest_id = `CSS.escape('trains_' + #{active_entity.id})`
        Lib::CardAnimation.fly(source_selector, "##{escaped_dest_id}") do
          process_action(Engine::Action::BuyTrain.new(
            active_entity,
            train: train,
            price: price_value
          ))
        end
      end

      def pd_props
        {
          style: {
            backgroundColor: 'salmon',
            color: 'black',
          },
        }
      end

      def render_choice_menu(title, options, cancel_handler)
        menu_elements = [
          h(:div,
            { style: { fontSize: '0.75rem', fontWeight: 'bold', marginBottom: '0.4rem', color: '#333', whiteSpace: 'nowrap' } }, title),
        ]

        options.each do |opt|
          menu_elements << h(:button, {
                               style: {
                                 display: 'block',
                                 width: '100%',
                                 marginBottom: '0.2rem',
                                 cursor: 'pointer',
                                 fontSize: '0.75rem',
                                 fontWeight: 'bold',
                                 padding: '3px 6px',
                                 backgroundColor: '#ffffff',
                                 border: '1px solid #cc0000',
                                 borderRadius: '3px',
                               },
                               on: { click: opt[:action] },
                             }, opt[:label])
        end

        menu_elements << h(:button, {
                             style: {
                               display: 'block',
                               width: '100%',
                               cursor: 'pointer',
                               fontSize: '0.75rem',
                               padding: '3px 6px',
                               backgroundColor: '#e0e0e0',
                               border: '1px solid #999',
                               borderRadius: '3px',
                               marginTop: '0.2rem',
                             },
                             on: { click: cancel_handler },
                           }, 'Cancel')

        h(:div, {
            style: {
              position: 'absolute',
              top: '105%',
              left: '50%',
              transform: 'translateX(-50%)',
              backgroundColor: '#ffffff',
              border: '2px solid #333333',
              borderRadius: '4px',
              padding: '0.5rem',
              zIndex: '9999',
              boxShadow: '0px 4px 10px rgba(0,0,0,0.3)',
            },
          }, menu_elements)
      end

      private

      def player_time_details(p)
        base_bank_seconds = if p.respond_to?(:thinking_time) && p.thinking_time
                              p.thinking_time.to_i
                            else
                              p.instance_variable_get(:@thinking_time).to_i
                            end

        base_bank_seconds = 300 if base_bank_seconds.zero? && !p.instance_variable_defined?(:@thinking_time)

        time_val = base_bank_seconds

        if p == active_player
          last_update_epoch = @game_data['updated_at'] || @game_data[:updated_at]
          turn_start_seconds = last_update_epoch ? last_update_epoch.to_i : Time.now.to_i
          elapsed_seconds = Time.now.to_i - turn_start_seconds
          time_val = base_bank_seconds - elapsed_seconds
        end

        abs_time = time_val.abs
        mins = (abs_time / 60).to_i
        secs = (abs_time % 60).to_i
        formatted_time = "#{'-' if time_val.negative?}#{mins}:#{'0' if secs < 10}#{secs}"
        [time_val, formatted_time]
      end

      def num_ipo_shares(corporation)
        if @game.separate_treasury?
          num_shares_of(@game.bank, corporation)
        elsif corporation.respond_to?(:num_ipo_shares)
          corporation.num_ipo_shares
        else
          num_shares_of(corporation, corporation)
        end
      end

      def min_width(entity)
        PLAYER_COL_MAX_WIDTH if entity.companies.size > 1 || @game.format_currency(entity.value).size > 6
      end
    end
  end
end

# rubocop:enable Layout/LineLength
