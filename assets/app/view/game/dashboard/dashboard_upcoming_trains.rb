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

      def train_tooltip(train)
        lines = []
        lines << "Train: #{train.name} (#{@game.info_train_name(train)})"
        lines << "Price: #{@game.info_train_price(train)}"

        # Trains rusted when this train is bought
        all_trains = (@game.respond_to?(:trains) && @game.trains) || (@depot.respond_to?(:trains) && @depot.trains) || []
        rusts = all_trains.select { |t| Array(t.rusts_on).map(&:to_s).include?(train.sym.to_s) || Array(t.rusts_on).map(&:to_s).include?(train.name.to_s) }.map(&:name).uniq
        lines << "• Rusts: #{rusts.join(', ')} train#{rusts.size > 1 ? 's' : ''}" if rusts.any?

        # When this train itself rusts or becomes obsolete
        lines << "• Rusted by: #{Array(train.rusts_on).join(', ')}" if train.rusts_on && !train.rusts_on.empty?
        lines << "• Obsoleted by: #{Array(train.obsolete_on).join(', ')}" if train.obsolete_on && !train.obsolete_on.empty?

        # Phase details: tiles, train limits, OR count, and events
        phases = if @game.respond_to?(:phases) && @game.phases.is_a?(Array)
                   @game.phases
                 elsif @game.respond_to?(:phase) && @game.phase.respond_to?(:phases)
                   @game.phase.phases
                 end

        if phases
          phase = phases.find { |p| p[:name].to_s == train.name.to_s || p[:train].to_s == train.sym.to_s }
          if phase
            lines << "• Phase: #{phase[:name]}"
            lines << "• Tiles: #{Array(phase[:tiles]).map(&:to_s).map(&:capitalize).join(', ')} available" if phase[:tiles] && !phase[:tiles].empty?
            lines << "• Operating Rounds: #{phase[:operating_rounds]}" if phase[:operating_rounds]

            if phase[:train_limit]
              limit = phase[:train_limit].is_a?(Hash) ? phase[:train_limit].map { |k, v| "#{k}: #{v}" }.join(', ') : phase[:train_limit]
              lines << "• Train Limit: #{limit}"
            end

            if phase[:events]
              phase[:events].each do |k, v|
                next unless v

                lines << "• Event: #{k.to_s.tr('_', ' ').capitalize}"
              end
            end

            if phase[:status]
              Array(phase[:status]).each do |st|
                lines << "• Status: #{st.to_s.tr('_', ' ').capitalize}"
              end
            end
          end
        end

        # Train-level specific events
        if train.events && !train.events.empty?
          train.events.each do |ev|
            ev_name = ev.is_a?(Hash) ? (ev[:type] || ev['type'] || ev.keys.first) : ev
            lines << "• Event: #{ev_name.to_s.tr('_', ' ').capitalize}" if ev_name
          end
        end

        lines.join("\n")
      end

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
          tooltip = train_tooltip(train)

          h(:div, {
            attrs: { title: tooltip },
            style: {
              display: 'flex',
              flexDirection: 'row',
              alignItems: 'center',
              justifyContent: 'space-between',
              padding: '2px 4px',
              borderBottom: '1px solid #e0e0e0',
              gap: '0.5rem',
              cursor: 'help',
            },
          }, [
            h(:div, { attrs: { class: 'game-card', title: tooltip }, style: { margin: '0', minWidth: '3.2rem', padding: '0 4px', fontSize: '0.8rem', height: '1.3rem' } }, name),
            h(:div, { style: { fontFamily: FONT_CASH, color: COLOR_CASH, fontWeight: 'bold', fontSize: '0.85rem', textAlign: 'right', flex: '1 1 auto' } }, price),
            h(:div, { style: { fontFamily: FONT_STD, fontSize: '0.85rem', fontWeight: 'bold', color: '#000000', minWidth: '2rem', textAlign: 'right' } }, rem_text),
          ])
        end.compact

        visible_rows = train_rows.take(4)
        hidden_rows = train_rows.drop(4)

        rows_content = if hidden_rows.empty?
                         visible_rows
                       else
                         details = h(:details, { style: { width: '100%', marginTop: '2px' } }, [
                           h(:summary, {
                             style: {
                               fontSize: '0.75rem',
                               textAlign: 'center',
                               color: COLOR_CASH,
                               cursor: 'pointer',
                               padding: '3px 4px',
                               backgroundColor: '#f0f0f0',
                               borderRadius: '3px',
                               fontWeight: 'bold',
                               listStyle: 'none',
                               userSelect: 'none',
                             },
                           }, "▼ +#{hidden_rows.size} more..."),
                           h(:div, { style: { display: 'flex', flexDirection: 'column' } }, hidden_rows),
                         ])
                         visible_rows + [details]
                       end

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
          h(:div, { style: { padding: '2px 4px', display: 'flex', flexDirection: 'column' } }, rows_content),
        ])
      end
    end
  end
end