# frozen_string_literal: true

require 'lib/settings'
require 'view/game/actionable'
require 'view/game/dashboard/dashboard_card'
require 'view/game/dashboard/railcard_helper'

module View
  module Game
    class DashboardBank < Snabberb::Component
      include Lib::Settings
      include Actionable
      include View::Game::Dashboard::RailcardHelper

      needs :game, store: true
      needs :train_handler, default: nil
      needs :show_loan_table, default: false, store: true

      FONT_STD = '"Helvetica Neue", Helvetica, Arial, sans-serif'
      FONT_MONEY = '"Courier New", Courier, monospace'
      FONT_CASH = '"Arial Black", Gadget, sans-serif'
      COLOR_CASH = '#4b0082' # Dark Purple (Indigo)
      COLOR_BANK_GREEN = 'var(--bg-market-zone, #e6f4ea)'

      def current_entity
        @game.round.active_step&.current_entity ||
          (@game.round.respond_to?(:current_entity) ? @game.round.current_entity : nil) ||
          @game.current_entity
      rescue NotImplementedError, StandardError
        nil
      end

      def actions_for(entity)
        return [] unless entity

        actions = []
        if @game.round.respond_to?(:actions_for)
          begin
            actions.concat(@game.round.actions_for(entity) || [])
          rescue NotImplementedError, StandardError
          end
        end
        step = @game.round.active_step
        if step&.respond_to?(:actions)
          begin
            actions.concat(step.actions(entity) || [])
          rescue NotImplementedError, StandardError
          end
        end
        if step&.respond_to?(:current_actions)
          begin
            actions.concat(step.current_actions || [])
          rescue NotImplementedError, StandardError
          end
        end
        actions.compact.map(&:to_s).uniq
      end

      def active_entity
        current_entity
      end

      def train_available_count(train, variant_name = nil)
        return '∞' if train.respond_to?(:unlimited) && train.unlimited

        if @game.depot.discarded.include?(train)
          @game.depot.discarded.count { |t| t.name == train.name || t.sym == train.sym }
        else
          count = @game.depot.upcoming.count do |t|
            t.name == train.name || t.sym == train.sym ||
              (variant_name && t.respond_to?(:variants) && t.variants&.key?(variant_name))
          end
          count = 1 if count.zero? && train.owner == @game.depot
          count
        end
      end

      def render
        title_props = {
          attrs: { class: 'column-zone-market' },
          style: {
            padding: '0.3rem',
            backgroundColor: COLOR_BANK_GREEN,
            color: '#000000',
            fontFamily: FONT_STD,
            fontSize: '1.1rem',
            fontWeight: 'bold',
            letterSpacing: '1px',
            textAlign: 'center',
          },
        }
        body_props = {
          style: {
            margin: '0.3rem 0.5rem 0.4rem',
            display: 'flex',
            flexDirection: 'column',
            gap: '0.35rem',
            backgroundColor: COLOR_BANK_GREEN,
          },
        }

        h('div#bank.card.column-zone-market', {
            style: {
              backgroundColor: COLOR_BANK_GREEN,
            },
          }, [
          h('div.title', title_props, 'The Bank'),
          h(:div, body_props, [
            render_financial_table,
            render_bank_trains,
            render_discarded_trains,
          ].compact),
        ])
      end

      def render_financial_table
        trs = []
        interest_change = (@game.interest_change if @game.respond_to?(:interest_change))

        if @game.game_end_check_values.include?(:bank)
          clean_bank_cash = @game.format_currency(@game.bank_cash)
          trs << h(:tr, { style: { backgroundColor: COLOR_BANK_GREEN } }, [
            h('td.middle',
              { style: { fontFamily: FONT_STD, textAlign: 'center', width: '50%', backgroundColor: COLOR_BANK_GREEN } }, 'Cash'),
            h('td.middle',
              { style: { fontFamily: FONT_MONEY, fontWeight: 'bold', color: COLOR_CASH, textAlign: 'center', width: '50%', backgroundColor: COLOR_BANK_GREEN } }, clean_bank_cash),
          ])
        end

        has_loans = @game.respond_to?(:total_loans) && @game.total_loans&.nonzero?
        has_interest = @game.respond_to?(:interest_rate) && @game.interest_rate

        if has_interest || has_loans
          if (rate = @game.interest_rate)
            trs << h(:tr, { style: { backgroundColor: COLOR_BANK_GREEN } }, [
              h('td.left', { style: { fontFamily: FONT_STD, backgroundColor: COLOR_BANK_GREEN } }, 'Interest per Loan'),
              h('td.right', { style: { fontFamily: FONT_MONEY, fontWeight: 'bold', backgroundColor: COLOR_BANK_GREEN } },
                @game.format_currency(rate)),
            ])
            if @game.respond_to?(:future_interest_rate)
              trs << h(:tr, { style: { backgroundColor: COLOR_BANK_GREEN } }, [
                h('td.left', { style: { fontFamily: FONT_STD, backgroundColor: COLOR_BANK_GREEN } }, 'Future Interest'),
                h('td.right', { style: { fontFamily: FONT_MONEY, fontWeight: 'bold', backgroundColor: COLOR_BANK_GREEN } },
                  @game.format_currency(@game.future_interest_rate)),
              ])
            end
          end

          entity = current_entity
          actions = actions_for(entity)
          can_take = actions.include?('take_loan') && @game.respond_to?(:loans) && @game.loans&.any?
          loan_val = @game.respond_to?(:loan_value) ? @game.loan_value(entity) : (@game.loans&.first&.amount || 0)
          taken = @game.respond_to?(:loans_taken) ? @game.loans_taken : 0
          total_available_loans = @game.respond_to?(:total_loans) ? @game.total_loans : 100
          total_dots = 100
          empty_count = [taken, total_dots].min
          available_dots = total_dots - empty_count

          loan_click = if can_take
                         lambda {
                           escaped_id = entity.id.to_s
                           target_selector = "#loan_empty_#{escaped_id}_0, #loans_#{escaped_id}"
                           Lib::LoanAnimation.fly('#bank_loan_active', target_selector) do
                             process_action(Engine::Action::TakeLoan.new(entity, loan: @game.loans.first))
                           end
                         }
                       end

          dots = []
          empty_count.times do
            dots << h(:span, {
                        style: {
                          display: 'inline-block',
                          width: '7px',
                          height: '7px',
                          border: '1px solid #dc3545',
                          borderRadius: '50%',
                          boxSizing: 'border-box',
                          pointerEvents: 'none',
                        },
                      })
          end

          available_dots.times do |i|
            d_attrs = {}
            d_attrs[:id] = 'bank_loan_active' if i.zero?
            dots << h(:span, {
                        attrs: d_attrs,
                        style: {
                          display: 'inline-block',
                          width: '7px',
                          height: '7px',
                          backgroundColor: '#dc3545',
                          borderRadius: '50%',
                          boxSizing: 'border-box',
                          pointerEvents: 'none',
                        },
                      })
          end

          loan_btn_props = {
            attrs: {
              id: (available_dots.zero? && can_take ? 'bank_loan_active' : 'bank_loan_btn'),
              type: 'button',
              title: can_take ? "Take loan for #{entity&.name} (#{@game.format_currency(loan_val)})" : "Loans taken: #{taken}/#{total_available_loans}",
            },
            style: {
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              width: '100%',
              padding: '6px 4px',
              backgroundColor: can_take ? '#fef2f2' : COLOR_BANK_GREEN,
              border: can_take ? '2px solid #dc2626' : '1px solid #86efac',
              borderRadius: '5px',
              cursor: can_take ? 'pointer' : 'default',
              boxShadow: can_take ? '0 1px 3px rgba(220,38,38,0.25)' : 'none',
              boxSizing: 'border-box',
            },
          }
          loan_btn_props[:on] = { click: loan_click } if loan_click

          trs << h(:tr, { style: { backgroundColor: COLOR_BANK_GREEN } }, [
            h(:td, { attrs: { colspan: 2 }, style: { padding: '4px 0', backgroundColor: COLOR_BANK_GREEN } }, [
              h(:button, loan_btn_props, [
                h(:div, {
                    style: {
                      display: 'grid',
                      gridTemplateColumns: 'repeat(20, 7px)',
                      gridAutoRows: '7px',
                      gap: '2px',
                      justifyContent: 'center',
                      alignItems: 'center',
                      lineHeight: '0',
                      pointerEvents: 'none',
                    },
                  }, dots),
              ]),
            ]),
          ])

          if interest_change
            toggle_loan_table = lambda do
              store(:show_loan_table, !@show_loan_table)
            end

            btn_table_props = {
              attrs: { title: "#{@show_loan_table ? 'Hide' : 'Show'} loan table" },
              style: {
                width: '4rem',
                margin: '0',
                cursor: 'pointer',
                backgroundColor: '#ffffff',
                border: '1px solid #999',
                borderRadius: '3px',
              },
              on: { click: toggle_loan_table },
            }
            trs << h(:tr, { style: { backgroundColor: COLOR_BANK_GREEN } }, [
              h('td.middle', { style: { fontFamily: FONT_STD, backgroundColor: COLOR_BANK_GREEN } }, 'Loan Table'),
              h('td.right', { style: { backgroundColor: COLOR_BANK_GREEN } },
                [h(:button, btn_table_props, (@show_loan_table ? 'Hide' : 'Show').to_s)]),
            ])

            if @show_loan_table
              total = 0
              interest_change.last.each do |price, available|
                total += available
                trs << h(:tr, { style: { backgroundColor: COLOR_BANK_GREEN } }, [
                  h('td.left', { style: { fontFamily: FONT_MONEY, backgroundColor: COLOR_BANK_GREEN } },
                    @game.format_currency(price)),
                  h('td.right', { style: { fontFamily: FONT_MONEY, backgroundColor: COLOR_BANK_GREEN } },
                    "#{available} (#{total})"),
                ])
              end
            end

            interest_change.first.each do |text, price_change|
              trs << h(:tr, { style: { backgroundColor: COLOR_BANK_GREEN } }, [
                h('td.left', { style: { fontFamily: FONT_STD, backgroundColor: COLOR_BANK_GREEN } }, text),
                h('td.right', { style: { fontFamily: FONT_MONEY, backgroundColor: COLOR_BANK_GREEN } },
                  @game.format_currency(price_change)),
              ])
            end
          end

          if @game.respond_to?(:loan_value) && (lv = @game.loan_value)
            trs << h(:tr, { style: { backgroundColor: COLOR_BANK_GREEN } }, [
              h('td.left', { style: { fontFamily: FONT_STD, backgroundColor: COLOR_BANK_GREEN } }, 'Loan Value'),
              h('td.right', { style: { fontFamily: FONT_MONEY, fontWeight: 'bold', backgroundColor: COLOR_BANK_GREEN } },
                @game.format_currency(lv)),
            ])
          end
        end

        active_step = @game.round.active_step
        if active_step.respond_to?(:seed_money) && active_step.seed_money
          clean_seed = @game.format_currency(active_step.seed_money).gsub(/[^0-9]/, '')
          trs << h(:tr, { style: { backgroundColor: COLOR_BANK_GREEN } }, [
            h('td.left', { style: { fontFamily: FONT_STD, backgroundColor: COLOR_BANK_GREEN } }, 'Seed Money'),
            h('td.right', { style: { fontFamily: FONT_CASH, color: COLOR_CASH, backgroundColor: COLOR_BANK_GREEN } }, clean_seed),
          ])
        end

        if @game.respond_to?(:unstarted_corporation_summary) && (summary = @game.unstarted_corporation_summary) && !summary.empty?
          trs << h(:tr, { style: { backgroundColor: COLOR_BANK_GREEN } }, [
            h('td.left', { style: { fontFamily: FONT_STD, backgroundColor: COLOR_BANK_GREEN } }, 'Unstarted Corps'),
            h('td.right', { style: { fontFamily: FONT_STD, backgroundColor: COLOR_BANK_GREEN } }, summary.first.to_s),
          ])
        end

        if @game.respond_to?(:other_bank_info) && @game.other_bank_info
          trs << h(:tr, { style: { backgroundColor: COLOR_BANK_GREEN } }, [
            h('td.left', { style: { fontFamily: FONT_STD, backgroundColor: COLOR_BANK_GREEN } },
              @game.other_bank_info.first.to_s),
            h('td.right', { style: { fontFamily: FONT_MONEY, backgroundColor: COLOR_BANK_GREEN } },
              @game.other_bank_info.last.to_s),
          ])
        end

        return nil if trs.empty?

        h(:table, { style: { borderCollapse: 'collapse', width: '100%', backgroundColor: COLOR_BANK_GREEN } }, trs)
      end

      def render_bank_trains
        return nil unless @game.respond_to?(:depot) && @game.depot

        step = @game.round.active_step
        train_buyable_step = step&.current_actions&.include?('buy_train')

        active_trains = if train_buyable_step && active_entity&.corporation? && step.respond_to?(:buyable_trains)
                          buyable_depot = step.buyable_trains(active_entity).select do |t|
                            (t.respond_to?(:from_depot?) && t.from_depot?) ||
                              t.owner == @game.depot ||
                              @game.depot.upcoming.include?(t)
                          end
                          buyable_depot.any? ? buyable_depot.uniq(&:name) : [@game.depot.upcoming.first].compact
                        else
                          [@game.depot.upcoming.first].compact
                        end

        return nil if active_trains.empty?

        train_cards = []

        active_trains.each do |train|
          variants = if train.respond_to?(:names_to_prices) && train.names_to_prices && !train.names_to_prices.empty?
                       train.names_to_prices
                     else
                       { train.name => train.price }
                     end

          variants.each do |variant_name, price|
            card_classes = %w[game-card card-train]
            click_handler = nil

            if train_buyable_step && active_entity&.corporation?
              can_afford = active_entity.cash >= price || active_entity.trains.empty?

              if can_afford
                card_classes << 'action-buy'
                card_classes << 'clickable'
                click_handler = lambda {
                  variant_str = variant_name.to_s
                  if @train_handler
                    @train_handler.call(train, price, variant_str)
                  else
                    process_action(Engine::Action::BuyTrain.new(
                      active_entity,
                      train: train,
                      price: price,
                      variant: (variant_str == train.name.to_s ? nil : variant_str)
                    ))
                  end
                }
              end
            end

            available_count = train_available_count(train, variant_name)
            dom_id = "bank_train_#{train.id}_#{variant_name.to_s.tr('/', '_')}"
            card_el = render_railcard(variant_name.to_s, card_classes, click_handler, entity: train)

            train_cards << h(:div, { attrs: { id: dom_id }, style: { display: 'inline-block', margin: '2px', textAlign: 'center', verticalAlign: 'top', backgroundColor: COLOR_BANK_GREEN } }, [
                card_el,
                h(:div, { style: { marginTop: '2px', whiteSpace: 'nowrap' } }, [
                  h(:span,
                    { style: { fontFamily: FONT_CASH, color: COLOR_CASH, fontSize: '0.75rem', fontWeight: 'bold' } }, @game.format_currency(price)),
                  h(:span,
                    { style: { fontFamily: FONT_STD, color: '#555555', fontSize: '0.72rem', marginLeft: '3px' } }, "(#{available_count})"),
                ]),
              ])
          end
        end

        return nil if train_cards.empty?

        h(:div, {
            style: {
              marginTop: '0.2rem',
              textAlign: 'center',
              backgroundColor: COLOR_BANK_GREEN,
            },
          }, [
          h(:div, { style: { fontSize: '0.8rem', fontWeight: 'bold', marginBottom: '0.2rem', fontFamily: FONT_STD, backgroundColor: COLOR_BANK_GREEN } },
            'Bank Depot:'),
          h(:div, { style: { display: 'flex', flexWrap: 'wrap', justifyContent: 'center', backgroundColor: COLOR_BANK_GREEN } },
            train_cards),
        ])
      end

      def render_discarded_trains
        return nil unless @game.respond_to?(:depot) && @game.depot && !@game.depot.discarded.empty?

        rust_schedule = Hash.new { |h, k| h[k] = [] }
        obsolete_schedule = Hash.new { |h, k| h[k] = [] }

        @game.depot.trains.group_by(&:name).each do |_name, trains|
          first = trains.first
          base_variant = first.variants.values.find { |v| !v[:ignore_rust_obsolete_schedule] }
          next unless base_variant

          base_rust = base_variant[:rusts_on]
          base_obsolete = base_variant[:obsolete_on]

          first.variants.each do |name, train_variant|
            next if train_variant[:ignore_rust_obsolete_schedule]

            train_variant[:rusts_on] ||= base_rust
            train_variant[:obsolete_on] ||= base_obsolete

            Array(train_variant[:rusts_on]).each do |rusts_on|
              rust_schedule[rusts_on].append(name) unless rust_schedule[rusts_on].include?(name)
            end
            Array(train_variant[:obsolete_on]).each do |obsolete_on|
              obsolete_schedule[obsolete_on].append(name) unless obsolete_schedule[obsolete_on].include?(name)
            end
          end
        end

        step = @game.round.active_step
        train_buyable_step = step&.current_actions&.include?('buy_train')

        rows = @game.depot.discarded.group_by(&:name).map do |_name, trains|
          train = trains.first
          price = @game.format_currency(train.price)
          count_text = trains.size.to_s

          card_classes = %w[game-card card-train]
          click_handler = nil

          if train_buyable_step && active_entity && active_entity.corporation?
            can_afford = active_entity.cash >= train.price || active_entity.trains.empty?

            if can_afford
              card_classes << 'action-buy'
              card_classes << 'clickable'
              click_handler = lambda {
                if @train_handler
                  @train_handler.call(train, train.price, nil)
                else
                  process_action(Engine::Action::BuyTrain.new(
                    active_entity,
                    train: train,
                    price: train.price
                  ))
                end
              }
            end
          end

          effects = []
          train.names_to_prices.keys.each do |key|
            if (rust = rust_schedule[key]) && !rust.empty?
              effects << "Rusts: #{rust.join(', ')}"
            end
          end

          if obsolete_schedule[train.name] && !obsolete_schedule[train.name].empty?
            effects << "Phases out: #{obsolete_schedule[train.name].join(', ')}"
          end

          card_el = render_railcard(train.name, card_classes, click_handler, entity: train)

          h(:tr, { style: { borderBottom: '1px solid #cccccc', backgroundColor: COLOR_BANK_GREEN } }, [
            h('td.center', { attrs: { id: "bank_train_#{train.id}" }, style: { padding: '0.4rem 0.6rem', verticalAlign: 'middle', backgroundColor: COLOR_BANK_GREEN } }, [
              card_el,
            ]),
            h('td.right', { style: { fontFamily: FONT_CASH, color: COLOR_CASH, padding: '0.4rem 0.6rem', fontWeight: 'bold', backgroundColor: COLOR_BANK_GREEN } }, [
              h(:div, price),
              h(:div, { style: { fontFamily: FONT_STD, fontSize: '0.72rem', fontWeight: 'normal', color: '#555555' } },
                "(#{count_text})"),
            ]),
            h('td.left', { style: { fontFamily: FONT_STD, padding: '0.4rem 0.6rem', fontSize: '0.8rem', color: '#444444', verticalAlign: 'middle', backgroundColor: COLOR_BANK_GREEN } },
              effects.join(' | ')),
          ])
        end

        h(:div, {
            style: {
              marginTop: '0.4rem',
              paddingTop: '0.4rem',
              borderTop: '1px solid #bbbbbb',
              backgroundColor: COLOR_BANK_GREEN,
            },
          }, [
          h(:div,
            { style: { fontSize: '0.8rem', fontWeight: 'bold', marginBottom: '0.3rem', fontFamily: FONT_STD, textAlign: 'center', backgroundColor: COLOR_BANK_GREEN } }, 'Bank Pool (Discarded):'),
          h(:div, { style: { overflowX: 'auto', backgroundColor: COLOR_BANK_GREEN } }, [
            h(:table, { style: { borderCollapse: 'collapse', width: '100%', fontSize: '0.85rem', backgroundColor: COLOR_BANK_GREEN } }, [
              h(:thead, [
                h(:tr, { style: { borderBottom: '2px solid #333333', backgroundColor: COLOR_BANK_GREEN } }, [
                  h('th.center', { style: { padding: '0.4rem 0.6rem', backgroundColor: COLOR_BANK_GREEN } }, 'Type'),
                  h('th.right', { style: { padding: '0.4rem 0.6rem', backgroundColor: COLOR_BANK_GREEN } }, 'Price'),
                  h('th.left', { style: { padding: '0.4rem 0.6rem', backgroundColor: COLOR_BANK_GREEN } }, 'Effect'),
                ]),
              ]),
              h(:tbody, { style: { backgroundColor: COLOR_BANK_GREEN } }, rows),
            ]),
          ]),
        ])
      end
    end
  end
end
