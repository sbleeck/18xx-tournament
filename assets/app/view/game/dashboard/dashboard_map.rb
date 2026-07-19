# frozen_string_literal: true

require '../lib/storage'
require '../lib/settings'
require 'view/game/axis'
require 'view/game/hex'
require 'view/game/tile_confirmation'
require 'view/game/tile_selector'
require 'view/game/token_selector'
require 'view/game/part/track'
require 'view/game/part/cities'
require 'view/game/part/towns'
require 'view/game/part/revenue'

# 1. Existing Track Monkey Patch
module View
  module Game
    module Part
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

      # 2. Fancy Values Overlay for Cities
      class Cities < Base
        unless method_defined?(:orig_render)
          alias orig_render render

          def render
            base_nodes = orig_render # Generate standard cities layout[cite: 8]

            # Extract numerical revenue text if available
            rev_entries = @tile.respond_to?(:revenue_to_render) ? @tile.revenue_to_render : []
            return base_nodes if rev_entries.empty?

            rev_text = rev_entries.first.to_s

            # Overlay a comically large text indicator over the node area
            base_nodes << h(:text, {
                              attrs: {
                                x: '0',
                                y: '5',
                                'text-anchor': 'middle',
                                fill: '#ff00ff', # Screaming Neon Magenta
                                stroke: '#ffffff',
                                'stroke-width': '2px',
                              },
                              style: {
                                fontSize: '110px', # 5x larger than standard map labels
                                fontWeight: '900',
                                fontFamily: '"Impact", "Arial Black", sans-serif',
                                pointerEvents: 'none',
                                zIndex: '9999',
                              },
                            }, rev_text)

            base_nodes
          end
        end
      end

      # 3. Fancy Values Overlay for Towns
      class Towns < Snabberb::Component
        unless method_defined?(:orig_render)
          alias orig_render render

          def render
            base_nodes = orig_render # Generate standard towns layout[cite: 9]

            rev_entries = @tile.respond_to?(:revenue_to_render) ? @tile.revenue_to_render : []
            return base_nodes if rev_entries.empty?

            rev_text = rev_entries.first.to_s

            base_nodes << h(:text, {
                              attrs: {
                                x: '0',
                                y: '5',
                                'text-anchor': 'middle',
                                fill: '#00ffff', # Screaming Neon Cyan to contrast with cities
                                stroke: '#000000',
                                'stroke-width': '2px',
                              },
                              style: {
                                fontSize: '110px',
                                fontWeight: '900',
                                fontFamily: '"Impact", "Arial Black", sans-serif',
                                pointerEvents: 'none',
                                zIndex: '9999',
                              },
                            }, rev_text)

            base_nodes
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
        actions = step&.actions(current_entity) || []

        unless (laid_hexes = @historical_laid_hexes)
          laid_hexes = @game.round.respond_to?(:laid_hexes) ? @game.round.laid_hexes : []
        end
        selected_hex = @tile_selector&.hex
        @hexes << @hexes.delete(selected_hex) if @hexes.include?(selected_hex)

        routes = @routes
        routes = @historical_routes if routes.none?

        # Identify which action layer is currently active
        track_action_active = actions.include?('lay_tile')
        token_action_active = actions.include?('place_token') || actions.include?('hex_token')

        @hexes.map! do |hex|
          clickable = @show_starting_map ? false : step&.available_hex(entity_or_entities, hex)
          opacity = 1.0

          base_hex = h(
            Hex,
            hex: hex,
            opacity: @show_starting_map ? 1.0 : (@opacity || opacity),
            entity: current_entity,
            clickable: clickable,
            actions: actions,
            routes: routes,
            # Force false to block hex.rb from rendering its default dotted overlay frames
            highlight: false,
          )

          # Determine border color based on the current active phase context
          border_color = nil
          if clickable
            if track_action_active
              border_color = '#dc3545' # Solid Red for Track Build
            elsif token_action_active
              # Validate that the hex possesses token slots (cities or towns) before allowing green highlight
              has_tokenable_slots = hex.tile && ((hex.tile.respond_to?(:cities) && hex.tile.cities.any?) || (hex.tile.respond_to?(:towns) && hex.tile.towns.any?))

              if has_tokenable_slots
                border_color = '#28a745' # Solid Green for Token Laying spots strictly
              end

            end
          end

          if border_color
            # Calculate coordinates for positioning our overlay highlight group
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
              # Tile selector not for the map
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

        # Build an independent, flat overlay array of un-rotated texts for valid revenue spots
        fancy_value_overlays = []

        if @raw_hex_list
          @raw_hex_list.each do |hex|
            next if hex.empty

            rev_entries = hex.tile && hex.tile.respond_to?(:revenue_to_render) ? hex.tile.revenue_to_render : []
            next if rev_entries.empty?

            # Extract base numerical center amount string
            val_string = rev_entries.first.to_s

            # Calculate absolute grid layout centers
            hx, hy = Hex.coordinates(hex, @start_pos)

            # Translate coordinates by map's internal padding parameters
            final_cx = hx + map_x
            final_cy = hy + map_y + 12 # Centering adjustment factor

            fancy_value_overlays << h(:text, {
                                        attrs: {
                                          x: final_cx.to_s,
                                          y: final_cy.to_s,
                                          'text-anchor': 'middle',
                                          'dominant-baseline': 'central',
                                          fill: '#ffffff',            # Thick white inner fill
                                          stroke: '#000000',          # Solid black contour frame
                                          'stroke-width': '5px',      # High-visibility contrast stroke
                                        },
                                        style: {
                                          fontSize: '48px !important', # Force massive sizing over .scaler-content overrides
                                          fontWeight: '900',
                                          fontFamily: '"Impact", "Arial Black", Charcoal, sans-serif',
                                          pointerEvents: 'none',
                                        },
                                      }, val_string)
          end
        end

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
            # Append our high-visibility layer on top of the base coordinate graphics group
            h(:g, { attrs: { id: 'dashboard-fancy-values' } }, fancy_value_overlays),
          ]),
        ])
      end

      def map_zoom
        Lib::Storage['map_zoom'] || 1
      end

      private

      def dashboard_hex_highlight(_hex, color_hex)
        # Use the standard highlight polygon path points calculated by the Engine geometry
        h(:polygon, {
            attrs: {
              points: Hex::HIGHLIGHT_POINTS,
              'fill-opacity': 0,
              stroke: color_hex,
              'stroke-width': Hex::HIGHLIGHT_STROKE_WIDTH + 3,
            },
            style: {
              pointerEvents: 'none', # Redundant backup safety to guarantee clicks pass straight through
            },
          })
      end
    end
  end
end
