# frozen_string_literal: true

require_relative '../../../step/waterfall_auction'

module Engine
  module Game
    module G1833NE
      module Step
        class WaterfallAuction < Engine::Step::WaterfallAuction
          def min_bid(company)
            return company.min_bid if may_purchase?(company)

            high_bid = highest_bid(company)
            return company.min_bid unless high_bid

            high_bid.price + min_increment
          end
        end
      end
    end
  end
end
