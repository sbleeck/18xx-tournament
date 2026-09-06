# frozen_string_literal: true

require_relative 'entities'
require_relative 'map'
require_relative 'meta'
require_relative '../company_price_up_to_face'
require_relative '../base'

module Engine
  module Game
    module G1833NE
      class Game < Game::Base
        include_meta(G1833NE::Meta)
        include Entities
        include Map
        include CompanyPriceUpToFace

        BANK_CASH = 10_000

        CERT_LIMIT = {
          3 => { 14 => 35, 13 => 33, 12 => 30, 11 => 28, 10 => 26, 9 => 24, 8 => 22, 7 => 19, 6 => 16, 5 => 14 },
          4 => { 14 => 26, 13 => 25, 12 => 23, 11 => 21, 10 => 20, 9 => 18, 8 => 16, 7 => 14, 6 => 12, 5 => 10 },
          5 => { 14 => 21, 13 => 20, 12 => 18, 11 => 17, 10 => 16, 9 => 14, 8 => 13, 7 => 11, 6 => 10, 5 => 8 },
        }.freeze

        STARTING_CASH = { 3 => 600, 4 => 450, 5 => 400 }.freeze

        CAPITALIZATION = :incremental

        MUST_SELL_IN_BLOCKS = true

        MARKET = [
          %w[0c 10 20 30 40p 50p 60p 70p 80p 90p 100p 112p 124p 137p 150p
             165 180 195 212 230 250 270 295 320 345 375 405 440 475 510 550 590 630 680 730],
           ].freeze

        PHASES = [
          {
            name: 'I',
            train_limit: 3,
            tiles: [:yellow],
            operating_rounds: 2,
            status: ['can_buy_companies'],
          },
          {
            name: 'II',
            train_limit: 3,
            on: '3/5',
            tiles: %i[yellow green],
            operating_rounds: 2,
            status: ['can_buy_companies'],
          },
          {
            name: 'III',
            on: '4/7',
            train_limit: 3,
            tiles: %i[yellow green],
            operating_rounds: 2,
          },
          {
            name: 'IV',
            on: '6/9',
            train_limit: 2,
            tiles: %i[yellow green brown],
            operating_rounds: 2,
          },
          {
            name: 'V',
            on: '7+3',
            train_limit: 2,
            tiles: %i[yellow green brown],
            operating_rounds: 2,
          },
        ].freeze

        TRAINS = [
          {
            name: '2',
            distance: 2,
            price: 75,
            num: 8,
            obsolete_on: '3+3',
            rusts_on: '5+3',
            variants: [
              {
                name: '2+1',
                distance: [{ 'nodes' => ['town'], 'pay' => 1, 'visit' => 1 },
                           { 'nodes' => %w[city offboard town], 'pay' => 2, 'visit' => 2 }],
                price: 100,
              },
            ],
          },
          {
            name: '3/5',
            distance: [{ 'nodes' => %w[city offboard town], 'pay' => 3, 'visit' => 5 }],
            price: 180,
            num: 5,
            obsolete_on: '6/9',
            rusts_on: '7+3',
            variants: [
              {
                name: '2+2',
                distance: [{ 'nodes' => ['town'], 'pay' => 2, 'visit' => 2 },
                           { 'nodes' => %w[city offboard town], 'pay' => 2, 'visit' => 2 }],
                price: 140,
              },
            ],
          },
          {
            name: '4/7',
            distance: [{ 'nodes' => %w[city offboard town], 'pay' => 4, 'visit' => 7 }],
            price: 320,
            num: 6,
            obsolete_on: '7+3',
            variants: [
              {
                name: '3+3',
                distance: [{ 'nodes' => ['town'], 'pay' => 3, 'visit' => 3 },
                           { 'nodes' => %w[city offboard town], 'pay' => 3, 'visit' => 3 }],
                price: 230,
              },
            ],
            events: [{ 'type' => 'close_companies' }],
          },
          {
            name: '6/9',
            distance: [{ 'nodes' => %w[city offboard town], 'pay' => 6, 'visit' => 9 }],
            price: 750,
            num: 3,
            variants: [
              {
                name: '5+3',
                distance: [{ 'nodes' => ['town'], 'pay' => 3, 'visit' => 3 },
                           { 'nodes' => %w[city offboard town], 'pay' => 5, 'visit' => 5 }],
                price: 640,
              },
            ],
            events: [
              { 'type' => 'remove_bonuses' },
              { 'type' => 'remove_reservations' },
            ],
          },
          {
            name: '7+3',
            distance: [{ 'nodes' => ['town'], 'pay' => 3, 'visit' => 3 },
                       { 'nodes' => %w[city offboard town], 'pay' => 7, 'visit' => 7 }],
            price: 950,
            num: 15,
          },
        ].freeze

        def new_auction_round
          Engine::Round::Auction.new(self, [
            G1833NE::Step::WaterfallAuction,
          ])
        end

        def stock_round
          Engine::Round::Stock.new(self, [
            Engine::Step::DiscardTrain,
            G1846::Step::Assign,
            G1846::Step::BuySellParShares,
          ])
        end

        def operating_round(round_num)
          @round_num = round_num
          G1846::Round::Operating.new(self, [
            G1846::Step::Bankrupt,
            G1846::Step::Assign,
            Engine::Step::SpecialToken,
            G1846::Step::SpecialTrack,
            G1846::Step::BuyCompany,
            G1846::Step::IssueShares,
            G1846::Step::TrackAndToken,
            Engine::Step::Route,
            G1846::Step::Dividend,
            Engine::Step::DiscardTrain,
            G1846::Step::BuyTrain,
            [G1846::Step::BuyCompany, { blocks: true }],
          ], round_num: round_num)
        end

        def takeover_round
          G1833NE::Round::Takeover.new(self, [
            G1833NE::Step::ViewAcquirable,
            G1833NE::Step::TakeoverCorporation,
          ])
        end

        def next_round!
          @round =
            case @round
            when Round::Stock
              @operating_rounds = @phase.operating_rounds
              reorder_players
              new_operating_round
            when Round::Operating
              if @round.round_num < @operating_rounds
                or_round_finished
                new_operating_round(@round.round_num + 1)
              elsif takeover_game? && @phase.name != 'I'
                or_round_finished
                or_set_finished
                new_takeover_round
              else
                @turn += 1
                or_round_finished
                new_stock_round
              end
            when Round::Takeover
              new_stock_round
            when init_round.class
              init_round_finished
              reorder_players
              new_stock_round
            end
        end

        def new_takeover_round
          @log << '-- Takeover Round -- '
          takeover_round(round_num)
        end

        def num_trains(train)
          if train[:name] == '6/9'
            takeover_game? ? 5 : 3
          end

          super
        end

        def takeover_game?
          @takeover_game ||= @optional_rules&.include?(:takeover_game)
        end
      end
    end
  end
end
