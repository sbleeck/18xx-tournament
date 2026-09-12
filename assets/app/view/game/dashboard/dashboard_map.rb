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

      class Revenue < Base
        needs :game, default: nil, store: true

        unless method_defined?(:orig_render)
          alias orig_render render
          def render
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

      def compute_axes(hexes)
        min, max = hexes.minmax
        (min..max).to_a
      end

      def hex_cost_display(step, entity_or_entities, hex)
        current_entity = Array(entity_or_entities).first
        base_cost = 0

        if @game.respond_to?(:upgrade_cost)
          begin
            base_cost += (@game.upgrade_cost(hex.tile, hex, current_entity) || 0)
          rescue StandardError
          end
        end

        if step.respond_to?(:get_tile_lay)
          begin
            tile_lay = step.get_tile_lay(current_entity)
            if tile_lay
              extra = hex.tile.color == :white ? (tile_lay[:cost] || 0) : (tile_lay[:upgrade_cost] || 0)
              base_cost += (extra || 0)
            end
          rescue StandardError
          end
        end

        border_objs = (hex.tile&.borders || []).select { |b| b.cost && b.cost.positive? }

        # No border costs: price is strictly fixed
        if border_objs.empty?
          return nil if base_cost.zero?

          return @game.respond_to?(:format_currency) ? @game.format_currency(base_cost) : "$#{base_cost}"
        end

        # Check connectivity to see if border crossing is mandatory or optional
        connected_edges = step.respond_to?(:hex_neighbors) ? (step.hex_neighbors(current_entity, hex) || []) : []
        cost_edges = border_objs.map(&:edge)

        border_total = border_objs.sum(&:cost)

        # If entity ONLY connects from the border edge(s), the crossing fee is mandatory and fixed
        if connected_edges.any? && connected_edges.all? { |e| cost_edges.include?(e) }
          total = base_cost + border_total
          return nil if total.zero?

          return @game.respond_to?(:format_currency) ? @game.format_currency(total) : "$#{total}"
        end

        # Cost depends on orientation: player can avoid border (min_cost) or cross border (max_cost)
        min_cost = base_cost
        max_cost = base_cost + border_total

        format_val = ->(val) { @game.respond_to?(:format_currency) ? @game.format_currency(val) : "$#{val}" }

        if min_cost.zero?
          "#{format_val.call(max_cost)}?"
        else
          "#{format_val.call(min_cost)}-#{format_val.call(max_cost)}"
        end
      end

      def render
        return h(:div, []) if (@layout = @game.layout) == :none

        @hexes = @show_starting_map ? @game.clone([]).hexes : @game.hexes.dup

        axes_hexes = @hexes.reject(&:ignore_for_axes)
        @cols = compute_axes(axes_hexes.map(&:x))
        @rows = compute_axes(axes_hexes.map(&:y))

        @start_pos = [@cols.first, @rows.first]
        @scale = 1.0

        step = @game.round.active_step(@selected_company)

        current_entity = @selected_company || step&.current_entity
        combo_entities = (@selected_combos || []).map { |id| @game.company_by_id(id) }
        entity_or_entities = combo_entities.empty? ? current_entity : [current_entity, *combo_entities]
        actions = step && current_entity ? (step.actions(current_entity) || []) : []

        selected_hex = @tile_selector&.hex
        @hexes << @hexes.delete(selected_hex) if @hexes.include?(selected_hex)

        routes = @routes
        routes = @historical_routes if routes.none?

        track_action_active = actions.include?('lay_tile')
        token_action_active = actions.include?('place_token') || actions.include?('hex_token')

        hovered_c_id = Lib::Storage['hovered_company_id']
        hovered_target_hexes = extract_hovered_hexes(hovered_c_id)

        @hexes.map! do |hex|
          clickable = @show_starting_map ? false : step&.available_hex(entity_or_entities, hex)

          base_hex = h(
            Hex,
            hex: hex,
            opacity: @show_starting_map ? 1.0 : (@opacity || 1.0),
            entity: current_entity,
            clickable: clickable,
            actions: actions,
            routes: routes,
            start_pos: @start_pos,
            highlight: false
          )

          border_color = nil
          if hovered_target_hexes.include?(hex.id.to_s)
            border_color = '#9333ea'
          elsif clickable && token_action_active
            token_nodes = (hex.tile&.cities || []) + (hex.tile&.towns || []).select { |t| t.respond_to?(:tokens) && t.tokens }
            has_tokens = !step.respond_to?(:available_tokens) || step.available_tokens(current_entity).any?
            already_tokened = token_nodes.any? do |node|
              (node.respond_to?(:tokened_by?) && node.tokened_by?(current_entity)) ||
                node.tokens.compact.any? { |t| t.corporation == current_entity }
            end
            open_slot = token_nodes.any? do |node|
              node.respond_to?(:open_slot?) ? node.open_slot?(current_entity) : node.tokens.any?(&:nil?)
            end

            border_color = '#ff8c00' if has_tokens && !already_tokened && open_slot
          end

          x, y = Hex.coordinates(hex, @start_pos)
          transform_str = "translate(#{x}, #{y})#{hex.layout == :pointy ? ' rotate(30)' : ''}"

          overlays = []

          if clickable && track_action_active && step.respond_to?(:potential_tiles) && step.potential_tiles(entity_or_entities,
                                                                                                            hex).any?
            overlays << h(:polygon, {
                            attrs: {
                              points: Hex::HIGHLIGHT_POINTS,
                              fill: 'url(#cyan-hatch)',
                              'pointer-events': 'none',
                            },
                          })

            overlays << h(:polygon, {
                            attrs: {
                              points: Hex::HIGHLIGHT_POINTS,
                              fill: 'none',
                              stroke: '#00ffff',
                              'stroke-width': '12',
                              'stroke-linejoin': 'round',
                              'stroke-linecap': 'square',
                              pathLength: '576',
                              'stroke-dasharray': '40 56',
                              'stroke-dashoffset': '20',
                              'pointer-events': 'none',
                            },
                          })

            cost_str = hex_cost_display(step, entity_or_entities, hex)
            if cost_str
              scale_factor = case cost_str.length
                             when 1..3 then 2.2
                             when 4    then 1.7
                             when 5    then 1.3
                             else 1.0
                             end

              rot_angle = hex.layout == :pointy ? 60 : 90

              overlays << h(:g, { attrs: { 'pointer-events': 'none' } }, [
                h(:polygon, {
                    attrs: {
                      points: '8.5,-80 48.5,-80 76.5,-32 36.5,-32',
                      fill: '#0f172a',
                      stroke: '#00ffff',
                      'stroke-width': '2.5',
                      'stroke-linejoin': 'round',
                    },
                  }),
                h(:g, {
                    attrs: {
                      transform: "translate(42.5, -56) rotate(#{rot_angle}) scale(#{scale_factor})",
                    },
                  }, [
                  h(:text, {
                      attrs: {
                        x: '0',
                        y: '0',
                        'text-anchor': 'middle',
                        'dominant-baseline': 'central',
                        fill: '#00ffff',
                        'font-weight': '900',
                        'font-family': 'Arial, Helvetica, sans-serif',
                        'letter-spacing': '-0.5px',
                      },
                    }, cost_str),
                ]),
              ])
            end
          end

          initial_stroke = border_color || 'transparent'
          initial_width = border_color ? (Hex::HIGHLIGHT_STROKE_WIDTH + 4) : 0

          hex_children = [
            base_hex,
            h(:g, {
                attrs: {
                  transform: transform_str,
                  class: 'hex-highlight-wrapper',
                },
                style: { pointerEvents: 'none' },
              }, [
              h(:polygon, {
                  attrs: {
                    points: Hex::HIGHLIGHT_POINTS,
                    class: 'hex-highlight-poly',
                    'data-orig-stroke': initial_stroke,
                    'data-orig-width': initial_width.to_s,
                    stroke: initial_stroke,
                    'stroke-width': initial_width.to_s,
                    'fill-opacity': '0',
                  },
                  style: { pointerEvents: 'none' },
                }),
              *overlays,
            ]),
          ]

          h(:g, {
              key: "dash-g-#{hex.id}",
              attrs: {
                id: "hex-#{hex.id}",
                class: "map-hex-container hex-#{hex.id}",
                'data-hex': hex.id.to_s,
              },
            }, hex_children)
        end
        @hexes.compact!

        map_w, map_h = map_size
        children = [render_map(map_w, map_h)]

        if current_entity && @tile_selector
          left = (@tile_selector.x + map_x) * @scale
          top = (@tile_selector.y + map_y) * @scale
          selector = render_selector(step, current_entity, entity_or_entities, actions, map_w, map_h, left, top)

          props = {
            style: { position: 'absolute', left: "#{left}px", top: "#{top}px" },
          }
          children.unshift(h(:div, props, [selector]))
        end

        props = {
          style: { width: 'max-content', height: 'max-content', margin: '0', position: 'relative' },
        }
        h(:div, props, children)
      end

      def render_selector(step, current_entity, entity_or_entities, actions, map_w, map_h, left, top)
        if @tile_selector.is_a?(Lib::TokenSelector)
          h(TokenSelector, zoom: 1.0)
        elsif @tile_selector.role != :map
        elsif @tile_selector.hex.tile != @tile_selector.tile
          h(TileConfirmation, zoom: 1.0)
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

          return h(:div) if select_tiles.empty?

          distance = TileSelector::DISTANCE * 1.0
          ts_ds = [TileSelector::DROP_SHADOW_SIZE - 5, 0].max

          h(TileSelector, layout: @layout, tiles: select_tiles, actions: actions, zoom: 1.0,
                          top_row: (top < distance),
                          left_col: (left < distance),
                          right_col: (map_w - left < distance + ts_ds),
                          bottom_row: (map_h - top < distance + ts_ds))
        end
      end

      def extract_hovered_hexes(hovered_c_id)
        return [] unless hovered_c_id

        target_hexes = []
        all_companies = @game.respond_to?(:companies) ? (@game.companies || []) : []

        hovered_company = all_companies.find do |c|
          c.id.to_s == hovered_c_id || (c.respond_to?(:sym) && c.sym.to_s == hovered_c_id)
        end ||
                          (if @game.respond_to?(:minors)
                             @game.minors.find do |m|
                               m.id.to_s == hovered_c_id || (m.respond_to?(:sym) && m.sym.to_s == hovered_c_id)
                             end
                           end) ||
                          @game.corporations.find do |corp|
                            corp.id.to_s == hovered_c_id || (corp.respond_to?(:sym) && corp.sym.to_s == hovered_c_id)
                          end

        if hovered_company
          if hovered_company.respond_to?(:coordinates) && hovered_company.coordinates
            Array(hovered_company.coordinates).each { |coord| target_hexes << coord.to_s }
          end
          if hovered_company.respond_to?(:city) && hovered_company.city&.respond_to?(:hex)
            target_hexes << hovered_company.city.hex.id.to_s
          end

          abilities = []
          if hovered_company.respond_to?(:all_abilities) && hovered_company.all_abilities
            abilities.concat(hovered_company.all_abilities)
          end
          abilities.concat(hovered_company.abilities) if hovered_company.respond_to?(:abilities) && hovered_company.abilities

          if @game.class.const_defined?(:COMPANIES)
            raw_def = @game.class::COMPANIES.find do |c_def|
              c_def[:sym].to_s == hovered_c_id || c_def[:name].to_s == hovered_c_id
            end
            if raw_def && raw_def[:abilities]
              raw_def[:abilities].each do |raw_ab|
                Array(raw_ab[:hexes]).each { |coord| target_hexes << coord.to_s } if raw_ab[:hexes]
                target_hexes << raw_ab[:hex].to_s if raw_ab[:hex]
              end
            end
          end

          abilities.each do |ab|
            Array(ab.hexes).each { |coord| target_hexes << coord.to_s } if ab.respond_to?(:hexes) && ab.hexes
            target_hexes << (ab.hex.respond_to?(:id) ? ab.hex.id : ab.hex).to_s if ab.respond_to?(:hex) && ab.hex
            Array(ab.coordinates).each { |coord| target_hexes << coord.to_s } if ab.respond_to?(:coordinates) && ab.coordinates

            target_corp = nil
            if ab.respond_to?(:corporation) && ab.corporation
              target_corp = @game.corporation_by_id(ab.corporation) || ab.corporation
            elsif ab.respond_to?(:minor) && ab.minor
              target_corp = (@game.respond_to?(:minor_by_id) ? @game.minor_by_id(ab.minor) : nil) || ab.minor
            end
            next unless target_corp && target_corp.respond_to?(:coordinates) && target_corp.coordinates

            Array(target_corp.coordinates).each do |coord|
              target_hexes << coord.to_s
            end
          end

          if hovered_company.respond_to?(:desc) && hovered_company.desc
            hovered_company.desc.scan(/\b[A-Za-z]\d{1,2}\b/).each do |h_id|
              target_hexes << h_id.upcase if @game.hex_by_id(h_id) || @game.hex_by_id(h_id.upcase)
            end
          end
        end
        target_hexes.uniq
      end

      def map_x
        GAP + FONT_SIZE
      end

      def map_y
        GAP + FONT_SIZE + (@layout == :flat ? (FONT_SIZE / 2.0) : FONT_SIZE)
      end

      def map_size
        if @layout == :flat
          [((((@cols.size * 1.5) + 0.5) * EDGE_LENGTH) + (2 * GAP)) * @scale,
           ((((@rows.size / 2.0) + 0.5) * SIDE_TO_SIDE) + (2 * GAP)) * @scale]
        else
          [(((((@cols.size / 2.0) + 0.5) * SIDE_TO_SIDE) + (2 * GAP)) + 1) * @scale,
           ((((@rows.size * 1.5) + 0.5) * EDGE_LENGTH) + (2 * GAP)) * @scale]
        end
      end

      def render_map(width, height)
        h(:svg, { attrs: { id: 'map', width: width.to_s, height: height.to_s } }, [
          h(:defs, [
            h(:pattern, {
                attrs: {
                  id: 'cyan-hatch',
                  width: '16',
                  height: '16',
                  patternUnits: 'userSpaceOnUse',
                  patternTransform: 'rotate(45)',
                },
              }, [
              h(:line, {
                  attrs: {
                    x1: '0',
                    y1: '0',
                    x2: '0',
                    y2: '16',
                    stroke: '#00ffff',
                    'stroke-width': '3.5',
                    'stroke-opacity': '0.5',
                  },
                }),
            ]),
          ]),

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
          ]),
        ])
      end

      def map_zoom
        Lib::Storage['map_zoom'] || 1
      end
    end
  end
end
