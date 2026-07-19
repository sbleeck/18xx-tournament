# frozen_string_literal: true

require '../lib/storage'
require '../lib/settings'
require 'view/game/axis'
require 'view/game/hex'
require 'view/game/tile_confirmation'
require 'view/game/tile_selector'
require 'view/game/token_selector'
require 'view/game/part/track'
require 'view/game/part/revenue'

module View
  module Game
    module Part
      # 1. Track Monkey Patch for wide, multicolor screaming route paths
      class Track < Snabberb::Component
        unless method_defined?(:orig_width_for_index)
          alias orig_width_for_index width_for_index
          alias orig_value_for_index value_for_index

          def width_for_index(path, index, path_indexes)
            base_width = orig_width_for_index(path, index, path_indexes)
            index ? (base_width * 2.5) : base_width
          end

          def value_for_index(index, prop, track)
            if index && prop == :color
              screaming_palette = ['#ff1493', '#00ffff', '#7fff00', '#ff00ff']
              screaming_palette[index.to_i] || '#ff1493'
            else
              orig_value_for_index(index, prop, track)
            end
          end
        end
      end

      # 2. Suppress native tiny map text blocks during the revenue calculation phase
      class Revenue < Base
        # Pull the game instance straight from Snabberb's global component store
        needs :game, default: nil, store: true

        unless method_defined?(:orig_render)
          alias orig_render render
          def render
            current_ent = @game&.round&.active_step&.current_entity
            actions = current_ent ? (@game.round.active_step.actions(current_ent) || []) : []

            is_revenue_phase = actions.include?('run_routes') || actions.include?('dividend') || actions.include?('payout')

            # Commented out for now to bring back native map numbers
            # is_revenue_phase ? h(:g) : orig_render
            orig_render
          end
        end
      end
    end
  end
end

module View
  module Game
    class DashboardMap < Snabberb::Component
      include Lib::Settings
      needs :game, store: true
      needs :tile_selector, default: nil, store: true
      needs :selected_route, default: nil, store: true
      needs :selected_company, default: nil, store: true
      needs :selected_combos, default: nil, store: true
      needs :opacity, default: nil
      needs :show_starting_map, default: false, store: true
      needs :routes, default: [], store: true
      needs :historical_laid_hexes, default: nil, store: true
      needs :historical_routes, default: [], store: true

      EDGE_LENGTH = 50
      SIDE_TO_SIDE = 87
      FONT_SIZE = 25
      GAP = 25
      SCALE = 0.5

      def compute_axes(hexes)
        min, max = hexes.minmax
        ((min.next)..(max.next)).to_a
      end

      def render
        return h(:div, []) if (@layout = @game.layout) == :none

        @hexes = @show_starting_map ? @game.clone([]).hexes : @game.hexes.dup

        axes_hexes = @hexes.reject(&:ignore_for_axes)
        @cols = compute_axes(axes_hexes.map(&:x))
        @rows = compute_axes(axes_hexes.map(&:y))

        @start_pos = [@cols.first, @rows.first]
        @scale = SCALE * map_zoom

        step = @game.round.active_step(@selected_company)
        current_entity = @selected_company || step&.current_entity
        combo_entities = (@selected_combos || []).map { |id| @game.company_by_id(id) }
        entity_or_entities = combo_entities.empty? ? current_entity : [current_entity, *combo_entities]
        actions = step && current_entity ? (step.actions(current_entity) || []) : []

        unless (laid_hexes = @historical_laid_hexes)
          laid_hexes = @game.round.respond_to?(:laid_hexes) ? @game.round.laid_hexes : []
        end
        selected_hex = @tile_selector&.hex
        @hexes << @hexes.delete(selected_hex) if @hexes.include?(selected_hex)

        routes = @routes
        routes = @historical_routes if routes.none?

        track_action_active = actions.include?('lay_tile')
        token_action_active = actions.include?('place_token') || actions.include?('hex_token')

        # Verify if we are strictly in the active revenue phase
        revenue_phase_active = actions.include?('run_routes') || actions.include?('dividend') || actions.include?('payout')
        @fancy_value_overlays = []

        @hexes.map! do |hex|
          clickable = @show_starting_map ? false : step&.available_hex(entity_or_entities, hex)
          opacity = 1.0

          # # Cache data fields synchronously to prevent asynchronous flickering
          # if revenue_phase_active && !hex.empty && hex.tile
          #   rev_entries = hex.tile.respond_to?(:revenue_to_render) ? hex.tile.revenue_to_render : []
          #   if rev_entries.any?
          #     val_string = rev_entries.first.to_s
          #     hx, hy = Hex.coordinates(hex, @start_pos)
          #     final_cx = hx + map_x
          #     final_cy = hy + map_y + 12

          #     @fancy_value_overlays << h(:text, {
          #                                  key: "fancy-txt-#{hex.id}",
          #                                  attrs: {
          #                                    x: final_cx.to_s,
          #                                    y: final_cy.to_s,
          #                                    'text-anchor': 'middle',
          #                                    'dominant-baseline': 'central',
          #                                    fill: '#ffffff',
          #                                    stroke: '#000000',
          #                                    'stroke-width': '6px',
          #                                  },
          #                                  style: {
          #                                    fontSize: '70px',
          #                                    fontWeight: '900',
          #                                    fontFamily: '"Impact", "Arial Black", Charcoal, sans-serif',
          #                                    paintOrder: 'stroke fill', # Forces outline behind fill to ensure perfect visibility
          #                                    pointerEvents: 'none',
          #                                  },
          #                                }, val_string)
          #   end
          # end

          base_hex = h(
            Hex,
            hex: hex,
            opacity: @show_starting_map ? 1.0 : (@opacity || opacity),
            entity: current_entity,
            clickable: clickable,
            actions: actions,
            routes: routes,
            start_pos: @start_pos,
            highlight: false, # Kill legacy dotted lines immediately
          )

          border_color = nil
          if clickable
            if track_action_active
              border_color = '#dc3545' # Red for active track building
            elsif token_action_active
              has_tokenable_slots = hex.tile && ((hex.tile.respond_to?(:cities) && hex.tile.cities.any?) || (hex.tile.respond_to?(:towns) && hex.tile.towns.any?))
              border_color = '#28a745' if has_tokenable_slots # Green strictly on valid token targets
            end
          end

          if border_color
            x, y = Hex.coordinates(hex, @start_pos)
            transform_str = "translate(#{x}, #{y})#{hex.layout == :pointy ? ' rotate(30)' : ''}"

            h(:g, { key: "dash-g-#{hex.id}" }, [
              base_hex,
              h(:g, { attrs: { transform: transform_str }, style: { pointerEvents: 'none' } }, [
                dashboard_hex_highlight(hex, border_color),
              ]),
            ])
          else
            base_hex
          end
        end
        @hexes.compact!

        children = [render_map]

        if current_entity && @tile_selector
          left = (@tile_selector.x + map_x) * @scale
          top = (@tile_selector.y + map_y) * @scale
          selector =
            if @tile_selector.is_a?(Lib::TokenSelector)
              h(TokenSelector, zoom: map_zoom)
            elsif @tile_selector.role != :map
            elsif @tile_selector.hex.tile != @tile_selector.tile
              h(TileConfirmation, zoom: map_zoom)
            else
              tiles = step.upgradeable_tiles(entity_or_entities, @tile_selector.hex)
              all_upgrades = @game.all_potential_upgrades(@tile_selector.hex.tile, selected_company: @selected_company)
              phase_colors = step.potential_tile_colors(current_entity, @tile_selector.hex)
              select_tiles = all_upgrades.map do |tile|
                real_tile = tiles.find { |t| t.name == tile.name }
                if real_tile
                  tiles.delete(real_tile)
                  [real_tile, nil]
                elsif !@game.tile_valid_for_phase?(tile, hex: @tile_selector.hex, phase_color_cache: phase_colors)
                  [tile, 'Later Phase']
                elsif @game.tiles.none? { |t| t.name == tile.name }
                  [tile, 'None Left']
                end
              end.compact

              select_tiles.append(*tiles.map { |t| [t, nil] })

              if select_tiles.empty?
                h(:div)
              else
                distance = TileSelector::DISTANCE * map_zoom
                width, height = map_size
                ts_ds = [TileSelector::DROP_SHADOW_SIZE - 5, 0].max
                left_col = left < distance
                right_col = width - left < distance + ts_ds
                top_row = top < distance
                bottom_row = height - top < distance + ts_ds

                h(TileSelector, layout: @layout, tiles: select_tiles, actions: actions, zoom: map_zoom,
                                top_row: top_row, left_col: left_col, right_col: right_col, bottom_row: bottom_row)
              end
            end

          props = {
            style: {
              position: 'absolute',
              left: "#{left}px",
              top: "#{top}px",
            },
          }
          children.unshift(h(:div, props, [selector]))
        end

        props = {
          style: {
            overflow: 'hidden',
            margin: '0',
            position: 'relative',
          },
        }

        h(:div, { style: { width: '100%', height: '100%', display: 'flex', justifyContent: 'center', alignItems: 'center' } }, [
          h(:div, props, children),
        ])
      end

      def map_x
        GAP + FONT_SIZE
      end

      def map_y
        GAP + (@layout == :flat ? (FONT_SIZE / 2) : FONT_SIZE)
      end

      def map_size
        if @layout == :flat
          [((((@cols.size * 1.5) + 0.5) * EDGE_LENGTH) + (2 * GAP)) * map_zoom,
           ((((@rows.size / 2) + 0.5) * SIDE_TO_SIDE) + (2 * GAP)) * map_zoom]
        else
          [(((((@cols.size / 2) + 0.5) * SIDE_TO_SIDE) + (2 * GAP)) + 1) * map_zoom,
           ((((@rows.size * 1.5) + 0.5) * EDGE_LENGTH) + (2 * GAP)) * map_zoom]
        end
      end

      def render_map
        width, height = map_size

        props = {
          attrs: {
            id: 'map',
            width: width.to_s,
            height: height.to_s,
          },
        }

        h(:svg, props, [
          h(:g, { attrs: { transform: "scale(#{@scale})" } }, [
            h(:g, { attrs: { id: 'map-hexes', transform: "translate(#{map_x} #{map_y})" } }, @hexes),
            h(Axis,
              cols: @cols,
              rows: @rows,
              axes: @game.axes,
              layout: @layout,
              font_size: FONT_SIZE,
              gap: GAP,
              map_x: map_x,
              map_y: map_y,
              start_pos: @start_pos),
            # Append un-rotated flat overlay layer completely clear of tile rotations
            h(:g, { attrs: { id: 'dashboard-fancy-values' } }, @fancy_value_overlays || []),
          ]),
        ])
      end

      def map_zoom
        Lib::Storage['map_zoom'] || 1
      end

      private

      def dashboard_hex_highlight(_hex, color_hex)
        h(:polygon, {
            attrs: {
              points: Hex::HIGHLIGHT_POINTS,
              'fill-opacity': 0,
              stroke: color_hex,
              'stroke-width': Hex::HIGHLIGHT_STROKE_WIDTH + 3,
            },
            style: {
              pointerEvents: 'none',
            },
          })
      end
    end
  end
end
