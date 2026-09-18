# frozen_string_literal: true

# backtick_javascript: true

require 'view/game/actionable'
require 'lib/settings'
require 'view/game/dashboard/railcard_helper'

module View
  module Game
    module Dashboard
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

          actions = actions_for(entity)

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
              (if @game.respond_to?(:companies)
                 @game.companies.find do |c|
                   c.id.to_s == token.to_s || (c.respond_to?(:sym) && c.sym.to_s == token.to_s)
                 end
               end) ||
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
              h(:td, { style: { padding: '6px 8px', borderBottom: '1px solid #e2e8f0', width: '1%', whiteSpace: 'nowrap' } },
                [item_card]),
              h(:td, { style: { padding: '6px 8px', borderBottom: '1px solid #e2e8f0', width: '8rem', whiteSpace: 'nowrap' } },
                [choose_btn].compact),
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
              row_cells << h(:td, { style: { padding: '6px 8px', textAlign: 'center', borderBottom: '1px solid #e2e8f0' } },
                             [owned_tag])
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
              h(:td, { style: { padding: '6px 8px', borderBottom: '1px solid #e2e8f0', width: '1%', whiteSpace: 'nowrap' } },
                [blank_badge]),
              h(:td, { style: { padding: '6px 8px', borderBottom: '1px solid #e2e8f0', width: '8rem', whiteSpace: 'nowrap' } },
                [blank_btn]),
              *players.map do
                h(:td, { style: { padding: '6px 8px', textAlign: 'center', borderBottom: '1px solid #e2e8f0' } },
                  [h(:span, { style: { color: '#cbd5e1' } }, '-')])
              end,
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
                      h(:th,
                        { attrs: { colspan: '2' }, style: { padding: '6px 8px', textAlign: 'left', borderBottom: '2px solid #cbd5e1', color: '#475569' } }, 'Available Cards'),
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
                      h(:td,
                        { attrs: { colspan: '2' }, style: { padding: '8px', fontWeight: 'bold', borderTop: '2px solid #cbd5e1', color: '#334155' } }, 'Cash on Hand:'),
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
  end
end
