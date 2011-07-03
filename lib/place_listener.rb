class PlaceListener
  @@hash = {}
  @@logger = nil

  def self.start(id, place, logger=nil)
    core = PlaceListenerCore.new(place, logger)
    @@logger ||= logger
    @@hash[id.to_s] = core
    core.start
  end

  def self.next_turn(id)
    core = @@hash[id.to_s]
    if core
      core.next_turn
    end
  end

  def self.accept_cards(id, player_id, card_strings)
    core = @@hash[id.to_s]
    if core
      core.accept_cards(player_id, card_strings)
    end
  end

  private
  def self.debug(msg)
    if @@logger
      @@logger.debug(msg)
    end
  end

  class PlaceListenerCore
    INTERVAL = 0.5
    TIMEOUT = 10

    def initialize(place, logger)
      @place = place
      @logger = logger
    end

    def start
      debug("start")
      Game.where(:place_id => @place.id).each do |g|
        Game.delete(g.id)
      end
      @game_count = 0
      init_game
      send_websocket("start_place", @place.to_json.sub(/place/,"place_info"))
    end

    def next_turn
      debug("next_turn")
      debug("playing_player_count=#{playing_player_count}")
      case
      when @game == nil
        if @game_count < @place.game_count
          start_game
        else
          end_place
        end
      when playing_player_count == 1
        end_game
      else
        start_turn 
      end
    end

    def accept_cards(player_id, card_strings, time_out=false)
      debug("accept_cards timeout:#{time_out}")
      @accept = true
      cards = CardUtiles.to_hashs(card_strings)
      reset = false
      if !time_out && put_place?(player_id, cards)
        debug("success")
        update_turn(cards)
        case
        when @game_players[@turn_player_index].cards.length == 0
          end_player(@game_players[@turn_player_index])
          @turn_player_index = next_player(@turn_player_index)
          reset = true
        when @pass_players.length == (playing_player_count - 1)
          @turn_player_index = next_player(@turn_player_index)
          reset = true
        when @game_place.any?{|card| card[:number] == 8}
          reset = true
        else
          @turn_player_index = next_player(@turn_player_index)
        end
      else
        debug("miss")
        miss_end_player(@game_players[@turn_player_index])
        @turn_player_index = next_player(@turn_player_index)
        reset = true
      end
      reset_place if reset
      end_turn(reset)
    end

    private
    def end_place
      debug("end_place")
      send_websocket("end_place", @place.to_json.sub(/place/,"place_info"))
    end

    def init_game
      debug("init_game")
      @game = nil
      @game_place = []
      @game_players = []
      @turn_player_index = 0
      @turn_count = 0
      @revolution = false
      @pass_players = []
      @ranks = Array.new(@place.players.length)
    end

    def start_game
      debug("start_game")
      @game_count += 1
      @game = @place.games.build(:no => @game_count,
                                 :status => 0,
                                 :place_info => get_place_info)
      @game.save
      create_players_hand
      @game_players = create_player_list
      if @game_count != 1
        card_change
      end
      send_websocket("start_game", @game.to_json)
    end

    def end_game
      debug("end_game")
      end_player(@game_players[@turn_player_index])
      @last_ranks = @ranks
      @game.status = 1
      @game.ranks  = @ranks
      @game.save
      send_websocket("end_game", @game.to_json)
      init_game
    end

    def start_turn
      debug("start_turn")
      @turn = nil
      @put_cards = []
      @turn_count += 1
      turn_player = @game_players[@turn_player_index]
      @turn = Turn.new(:game_id => @game.id,
                       :player_id => turn_player.id,
                       :no => @turn_count)
      @turn.place_cards = @game_place.map{|c| p=PlaceCard.new; p.card = c; p}
      @turn.save
      send_data = {:player => turn_player.user.name, 
                   :place_cards => @game_place,
                   :place_info => @game.place_info}
      @accept = false
      send_websocket("start_turn", send_data.to_json)
      timeout_check
    end

    def update_turn(cards)
      debug("update_turn")
      player = @game_players[@turn_player_index]
      player_cards = CardUtiles.reject(player.cards, cards)
      @put_cards = CardUtiles.find_all(player.cards, cards)
      @turn.turn_cards = @put_cards.map{|c| t=TurnCard.new; t.card = c; t}
      @turn.save
      player.cards = player_cards
      player.save
      if cards.length != 0
        @game_place = @put_cards
      else
        @pass_players << player.id
      end
    end

    def end_turn(reset)
      debug("end_turn")
      send_data = {:player => @turn.player.user.name, 
                   :turn_cards => @put_cards,
                   :reset_place => reset}
      send_websocket("end_turn", send_data.to_json)
    end

    def reset_place
      debug("reset_place:place=#{@game_place}")
      # set revolution
      if @game_place.length >= 4 && CardUtiles.pare?(@game_place)
        @revolution = !@revolution
        @game.place_info = get_place_info
        @game.save
      end
      # reset place
      @game_place = []
      @pass_players = []
    end

    def put_place?(player_id, cards)
      debug("put_place?")
      debug(cards)
      case
      when @turn == nil
        debug("turn nil")
        @turn_player_index = @game_players.index{|p| p.id == player_id}
        false
      when @turn.player.id != player_id
        debug("plyayer id not match")
        @turn_player_index = @game_players.index{|p| p.id == player_id}
        false
      when !CardUtiles.include?(@turn.player.cards, cards)
        debug("plyayer cards not include")
        false
      when @game_place.length != 0 && cards.length != 0 && @game_place.length != cards.length
        debug("length miss")
        false
      when !CardUtiles.yaku?(cards)
        debug("yaku miss")
        false
      when !CardUtiles.compare_yaku(@game_place, cards, @revolution)
        debug("yaku loss")
        false
      when CardUtiles.last_card_miss?(@turn.player.cards, cards, @revolution)
        debug("last card miss")
        false
      else
        true
      end
    end

    def end_player(player)
      debug("end_player")
      rank = nil
      @ranks.length.times do |i|
        unless @ranks[i]
          rank = Rank.new(:rank => i+1)
          rank.game = @game
          rank.player = player
          @ranks[i] = rank
          break
        end
      end
      send_data = {:player => player.user.name,
                   :rank => rank}
      send_websocket("end_player", send_data.to_json)
      sleep(INTERVAL)
    end

    def miss_end_player(player)
      debug("miss_end_player")
      rank = nil
      if player.cards.length != 0
        @ranks.length.downto(1) do |i|
          unless @ranks[i-1]
            rank = Rank.new(:rank => i)
            rank.game = @game
            rank.player = player
            @ranks[i-1] = rank
            break
          end
        end
        player.cards = []
        player.save
        send_data = {:player => player.user.name,
                     :rank => rank}
        send_websocket("end_player", send_data.to_json)
      else
        debug("alredy miss")
      end
      sleep(INTERVAL)
    end

    def create_players_hand
      debug("create_players_hand")
      hands = CardUtiles.create_hand(@place.players.length)
      @place.players.each_with_index do |player, i|
        player.cards = hands[i]
        player.save
        debug("#{player.user.name}:#{player.cards}")
      end
    end

    def create_player_list
      debug("create_player_list")
      list = []
      players = @place.players
      if @game_count == 1
        start_player = (Player.joins(:cards).where(:place_id => @place.id) &
                        Card.where(:mark => 2).where(:number => 3))[0]
        i = players.index(start_player)
      else
        first_player_id = @last_ranks.last.player_id
        i = players.index{|p| p.id == first_player_id}
      end
      m = players.length
      if i == 0
        list = players
      else
        list = players[i..(m-1)] + players[0..(i-1)]
      end
      list
    end

    def card_change
      debug("card_change")
      debug("last_ranks:#{@last_ranks}")
      sleep INTERVAL
      change(
        @game_players.find{|p| 
          p.id == @last_ranks[0].player_id},
        @game_players.find{|p|
          p.id == @last_ranks[@last_ranks.length - 1].player_id},
        2)
      change(
        @game_players.find{|p| 
          p.id == @last_ranks[1].player_id},
        @game_players.find{|p| 
          p.id == @last_ranks[@last_ranks.length - 2].player_id},
        1)
    end

    def change(a, b, change_count)
      debug("#{a.user.name}<->#{b.user.name}")
      a_sort_cards = CardUtiles.sort(a.cards)
      b_sort_cards = CardUtiles.sort(b.cards).reverse
      a_change = a_sort_cards.slice!(0,change_count)
      b_change = b_sort_cards.slice!(0,change_count)
      a.cards = a_sort_cards + b_change
      a.save
      b.cards = b_sort_cards + a_change
      b.save
      debug("#{a.user.name}_change:#{a_change}")
      debug("#{b.user.name}_change:#{b_change}")
    end

    def next_player(now_index)
      debug("next_player")
      index = now_index + 1
      index = 0 if @game_players.length  <= index
      case
      when @pass_players.include?(@game_players[index].id)
        next_player(index)
      when @game_players[index].cards.length == 0
        next_player(index)
      else
        index
      end
    end

    def timeout_check
      Thread.new do
        debug("timeout_check")
        begin
          timeout(TIMEOUT) do
            loop do
              break if @accept
              sleep 0.5 
            end
          end
        rescue Timeout::Error
          debug("timeout:#{@accept}")
          accept_cards(@turn.player.id, [], true) unless @accept
        end
      end
    end

    def playing_player_count
      count = 0
      @game_players.each{|p|
        debug("#{p.user.name}:#{p.cards.length}")
        count +=1 if p.cards.length != 0
      }
      count
    end

    def send_websocket(operation, json)
      debug("send_websocket")
      add = ",\"operation\":\"#{operation}\",\"place\":#{@place.id}}"
      param = json.sub(/}$/, add)
      debug("send_msg=#{param}")
      WebsocketSender.call(param)
    end

    def get_place_info
      if @revolution
        "Revolution"
      else
        "Nomal"
      end
    end

    def debug(msg)
      if @logger
        @logger.debug(msg)
      end
    end
  end
end
