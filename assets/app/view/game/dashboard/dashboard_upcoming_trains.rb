# frozen_string_literal: true

require 'lib/settings'
require 'view/game/dashboard/dashboard_card'

module View
  module Game
    class DashboardUpcomingTrains < Snabberb::Component
      include Lib::Settings

      needs :game

      FONT_STD = '"Helvetica Neue", Helvetica, Arial, sans-serif'
      FONT_MONEY = '"Courier New", Courier, monospace'
      FONT_CASH = '"Arial Black", Gadget, sans-serif'
      COLOR_CASH = '#4b0082' # Dark Purple (Indigo)

      def render
        return nil unless @game.respond_to?(:depot) && @game.depot

        @depot = @game.depot
        return nil if @depot.trains.empty?

        train_rows = @depot.trains.reject(&:reserved).group_by(&:sym).map do |sym, trains|
          remaining = @depot.upcoming.select { |t| t.sym == sym }
          next nil if remaining.empty?

          train = trains.first

          name = @game.info_train_name(train)
          price = @game.info_train_price(train)
          rem_text = train.unlimited ? '(∞)' : "(#{remaining.size})"

          h(:div, {
            style: {
              display: 'flex',
              flexDirection: 'row',
              alignItems: 'center',
              justifyContent: 'space-between',
              padding: '2px 4px',
              borderBottom: '1px solid #e0e0e0',
              gap: '0.5rem',
            },
          }, [
            h(:div, { attrs: { class: 'game-card' }, style: { margin: '0', minWidth: '3.2rem', padding: '0 4px', fontSize: '0.8rem', height: '1.3rem' } }, name),
            h(:div, { style: { fontFamily: FONT_CASH, color: COLOR_CASH, fontWeight: 'bold', fontSize: '0.85rem', textAlign: 'right', flex: '1 1 auto' } }, price),
            h(:div, { style: { fontFamily: FONT_STD, fontSize: '0.85rem', fontWeight: 'bold', color: '#000000', minWidth: '2rem', textAlign: 'right' } }, rem_text),
          ])
        end.compact

title_props = {
          attrs: { class: 'column-zone-market' },
          style: {
            padding: '0.3rem',
            backgroundColor: 'var(--bg-market-zone)',
            color: '#000000',
            fontFamily: FONT_STD,
            fontSize: '1.1rem',
            fontWeight: 'bold',
            letterSpacing: '1px',
            textAlign: 'center',
            borderBottom: '1px solid #b3b3b3',
          },
        }

            h('div#upcoming_trains.card.column-zone-market', { style: { minWidth: '130px', maxWidth: '210px' } }, [
            h('div.title', title_props, 'Upcoming Trains'),
          h(:div, { style: { padding: '2px 4px', display: 'flex', flexDirection: 'column' } }, train_rows),
        ])
      end
    end
  end
end