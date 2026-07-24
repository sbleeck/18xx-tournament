# frozen_string_literal: true

require_relative '../../../step/token'

module Engine
  module Game
    module G1835
      module Step
        class Token < Engine::Step::Token
          def can_afford_token?(token, cash)
            corp = token.corporation
            @game.log << "[DEBUG TOKEN] Checking afford for #{corp.name} ($#{cash})"
            
            @game.token_graph_for_entity(corp).tokenable_cities(corp).any? do |city|
              token_price(token, city.tile.hex) <= cash
            end
          end

          def token_price(token, hex)
            corp = token.corporation
            home_hex = @game.hex_by_id(corp.coordinates)
            return token.price unless home_hex && hex

            distance = home_hex.distance(hex)
            price = token.price + (distance ? distance * 20 : 0)
            
            @game.log << "[DEBUG TOKEN] #{corp.name} -> #{hex.id} | Dist: #{distance} | Price: #{price}M"
            price
          end

          def adjust_token_price_ability!(_entity, token, hex, _city, special_ability: nil)
            token.price = token_price(token, hex)
            [token, nil]
          end
        end
      end
    end
  end
end