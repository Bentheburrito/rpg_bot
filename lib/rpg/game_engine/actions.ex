defmodule RPG.GameEngine.Actions do
  import RPG.GameEngine.Character, only: [is_conscious: 1]

  alias RPG.GameEngine.{Character, Item, Texts}
  alias RPG.Party

  def approach(%Party{} = party, _actor_id, subject_id) when not is_map_key(party.directory, subject_id) do
    {:invalid, "(There's nothing/no one called '#{subject_id}' to approach)"}
  end

  def approach(%Party{} = party, actor_id, subject_id) do
    case party.proximity_map do
      %{^actor_id => leader, ^subject_id => leader} ->
        {:invalid, "(You are already close to #{subject_id})"}

      %{^subject_id => leader} ->
        actor_name = party.directory[actor_id].name
        subject_name = party.directory[subject_id].name

        {
          :ok,
          %Party{party | proximity_map: Map.put(party.proximity_map, actor_id, leader)},
          "#{actor_name} approaches #{subject_name}"
        }
    end
  end

  def disengage(%Party{state: :roaming} = party, _actor_id),
    do: {:ok, party, "(You are not in an engagement, there's no reason to disengage)"}

  def disengage(%Party{} = party, actor_id) do
    case Map.get_and_update!(party.proximity_map, actor_id, fn leader_id -> {leader_id, actor_id} end) do
      {^actor_id, new_proximity} ->
        party.proximity_map
        |> Enum.filter(fn {id, leader} -> leader == actor_id and id != actor_id end)
        |> case do
          [{first_id, _} | _] ->
            new_proximity =
              Map.new(new_proximity, fn
                # leave the actor alone in this case since they're disengaging from enemies that approached them first
                {^actor_id, ^actor_id} = entry -> entry
                # "elect" new leader
                {id, ^actor_id} -> {id, first_id}
                entry -> entry
              end)

            characters = for {character, ^first_id} <- new_proximity, do: character

            {:ok, %Party{party | proximity_map: new_proximity},
             "#{party.directory[actor_id].name} disengaged from #{Enum.map_join(characters, ", ", &party.directory[&1].name)}"}

          [] ->
            {:invalid, "(You're not close to anyone - no need to disengage)"}
        end

      {old_leader, new_proximity} ->
        characters = for {character, ^old_leader} <- new_proximity, do: character

        {
          :ok,
          %Party{party | proximity_map: new_proximity},
          "#{party.directory[actor_id].name} disengaged from #{Enum.join(characters, ", ")}"
        }
    end
  end

  def swing(%Party{} = party, actor_id, item),
    do: {:ok, party, "#{party.directory[actor_id].name} swung their #{item} at...nothing? (Are they okay?)"}

  def swing(%Party{state: :roaming} = party, actor_id, item, subject_id) do
    case swing(%Party{party | state: :engagement}, actor_id, item, subject_id) do
      {:ok, party, response} ->
        {:ok, party, response <> "\n#{actor_id} has started a fight!"}

      {:invalid, response} ->
        {:invalid, response}
    end
  end

  def swing(%Party{} = party, actor_id, item, subject_id) do
    actor = party.directory[actor_id]

    with %Item{} = weapon <- Map.get(actor.inventory, item, :doesnt_have),
         %{^actor_id => leader, ^subject_id => leader} <- party.proximity_map,
         %Character{} = subject <- party.directory[subject_id] do
      case Character.attack(actor, weapon, subject) do
        {:ok, hit_roll, hit_mod, subject_ac, damage_roll, damage_mod, new_subject} ->
          {emoji, attack_result} =
            if not is_conscious(new_subject) do
              {"☠️", "incapacitated them"}
            else
              {"⚔️", "left them with a gruesome wound"}
            end

          {
            :ok,
            %Party{party | directory: Map.put(party.directory, subject_id, new_subject)},
            """
            *#{actor.name} rolled a #{hit_roll} #{Texts.modifier(hit_mod, "proficiency bonus")} = #{hit_roll + hit_mod} to hit, which beats #{subject}'s AC of #{subject_ac}!*\s\s
            *#{actor.name} rolled a #{damage_roll} #{Texts.modifier(damage_mod, "armor resist")} = #{Character.cur_hp(subject) - Character.cur_hp(new_subject)} damage!*\s\s
            #{emoji} #{actor.name} swung their #{weapon.name} at #{subject} and #{attack_result}!
            """
          }

        {:miss, hit_roll, hit_mod, subject_ac} ->
          {
            :ok,
            party,
            """
            *#{actor.name} rolled a #{hit_roll} #{Texts.modifier(hit_mod, "proficiency bonus")} = #{hit_roll + hit_mod} to hit, which lost to #{subject}'s AC of #{subject_ac}!*\s\s
            #{actor.name} swung their #{weapon.name} at #{subject} and missed!
            """
          }
      end
    else
      :doesnt_have ->
        {:invalid, "(You don't have a(n) '#{item}' in your inventory)"}

      prox_map when is_map(prox_map) and is_map_key(prox_map, subject_id) ->
        {:invalid, "(You are not close enough to #{subject_id}, you must `approach` them before `swing`ing.)"}

      not_a_char ->
        if is_map_key(party.directory, subject_id) do
          {:ok, party, "#{actor.name} swung their #{item} at the #{not_a_char}. It didn't seem to do anything"}
        else
          {:invalid, "(There is no #{subject_id})"}
        end
    end
  end

  # TODO: add shoot clause that checks if the item can actually be shot. If not, suggest `throw` instead.
  def shoot(%Party{}, _actor_id, item), do: {:invalid, "(shoot #{item} at what?)"}

  def shoot(%Party{state: :roaming} = party, actor_id, item, subject_id) do
    {:ok, party, response} = shoot(%Party{party | state: :engagement}, actor_id, item, subject_id)

    {:ok, party, response <> "\n#{actor_id} has started a fight!"}
  end

  def shoot(%Party{} = party, actor_id, item, subject_id) do
    # TODO: item proficiency, status effects
    actor = party.directory[actor_id]

    case party.directory[subject_id] do
      %Character{} = subject ->
        projectile_attack(party, actor, item, subject, "#{actor.name} shot at #{subject.name} with their #{item}")

      not_a_char ->
        {:ok, party, "#{actor.name} shot their #{item} at the #{not_a_char}. It didn't seem to do anything"}
    end
  end

  # TODO:
  # def shoot(%Party{} = party, actor_id, item, subject_id, ammo_item) do

  def throw(%Party{}, _actor_id, item), do: {:invalid, "(throw #{item} at what?)"}

  def throw(%Party{state: :roaming} = party, actor_id, item, subject_id) do
    {:ok, party, response} = throw(%Party{party | state: :engagement}, actor_id, item, subject_id)

    {:ok, party, response <> "\n#{actor_id} has started a fight!"}
  end

  def throw(%Party{} = party, actor_id, item, subject_id) do
    actor = party.directory[actor_id]

    case party.directory[subject_id] do
      %Character{} = subject ->
        projectile_attack(party, actor, item, subject, "#{actor.name} threw their #{item} at #{subject.name}")

      not_a_char ->
        {:ok, party, "#{actor.name} shot their #{item} at the #{not_a_char}. It didn't seem to do anything"}
    end
  end

  # def cast(%Party{} = party, actor_id, item), do: {party, "(cast #{item} at what?)"}

  # def cast(%Party{} = party, actor_id, item, subject) do
  #   # let's stop here, work out Characters (proficiencies), Items (attributes) first
  # end

  def drink(%Party{} = party, actor_id, item), do: consumable_action(party, actor_id, item, {"drink", "drank"})
  def eat(%Party{} = party, actor_id, item), do: consumable_action(party, actor_id, item, {"eat", "ate"})
  def consume(%Party{} = party, actor_id, item), do: consumable_action(party, actor_id, item, {"consume", "consumed"})

  def examine(%Party{} = party, actor_id, item) do
    # TODO: quest items, perception/intellegence check for things like recalling the history of an item.
    #       for now, just print the item description
    case party.directory do
      # item in actor's inventory
      %{^actor_id => %Character{inventory: %{^item => %Item{description: description}}} = actor} ->
        {:ok, party, "#{actor.name} inspects their #{item}:\n\n*#{description}*"}

      # item in the current area
      %{^item => %Item{description: description}} ->
        {:ok, party, "#{party.directory[actor_id].name} inspects the #{item}:\n\n*#{description}*"}

      _what_item? ->
        {:invalid, "(There isn't a(n) '#{item}' in your inventory or near by)"}
    end
  end

  def craft(%Party{} = party, actor_id, item) do
    # TODO: item crafting. The part "with" of an action will probably be for things like crafting ("craft soup with
    # mushrooms, carrots, potatoes"), and shooting bows with specific kinds of arrows ("shoot bow at gary the goblin
    # with frost arrow")
    {:ok, party,
     "#{party.directory[actor_id].name} tries to craft an #{item}, but realizes they don't have the ingredients"}
  end

  def grab(%Party{} = party, actor_id, item_name) do
    case Map.pop(party.directory, item_name, :not_in_directory) do
      # TODO: use String.jaro_distance to maybe recommend other items found in the directory
      {:not_in_directory, _directory} ->
        {:invalid, "(There doesn't seem to be an #{item_name} to pick up)"}

      {item, directory} ->
        actor = directory[actor_id]

        case Character.add_to_inventory(actor, item) do
          {:ok, actor} ->
            {
              :ok,
              %Party{party | directory: Map.put(directory, actor_id, actor)},
              "#{actor.name} picked up a(n) '#{item}' and added it to their inventory"
            }

          {:error, :too_heavy} ->
            {:invalid, "(You can't pick up that #{item}, because you would be overencumbered)"}
        end
    end
  end

  def continue(%Party{state: :roaming} = party, _actor_id) do
    with {:ok, next_area} <- party.area.next_area(),
         {directory, _old_npcs} <- Map.split_with(party.directory, fn {id, _} -> id in party.member_ids end),
         {npc_map, next_state, exposition} <- next_area.init_area() do
      directory = Map.merge(npc_map, directory)
      prox_map = Map.new(directory, fn {key, _} -> {key, key} end)

      {:ok, %Party{party | area: next_area, state: next_state, directory: directory, proximity_map: prox_map},
       exposition}
    else
      :none -> {:invalid, "(There is no area to continue to from here.)"}
    end
  end

  def continue(%Party{}, _actor_id), do: {:invalid, "(You cannot continue to the next area while in an engagement.)"}

  def retreat(%Party{state: :roaming} = party, _actor_id) do
    with {:ok, prev_area} <- party.area.prev_area(),
         {directory, _old_npcs} <- Map.split_with(party.directory, fn {id, _} -> id in party.member_ids end),
         {npc_map, next_state, exposition} <- prev_area.init_area() do
      directory = Map.merge(npc_map, directory)
      prox_map = Map.new(directory, fn {key, _} -> {key, key} end)

      {:ok, %Party{party | area: prev_area, state: next_state, directory: directory, proximity_map: prox_map},
       exposition}
    else
      :none -> {:invalid, "(There is no area to retreat to from here. Onward!)"}
    end
  end

  def retreat(%Party{}, _actor_id), do: {:invalid, "(You cannot retreat to the previous area while in an engagement.)"}

  defp projectile_attack(%Party{} = party, actor_id, item, subject_id, verbiage) do
    %{name: actor_name} = actor = party.directory[actor_id]

    with {:has_item?, true} <- {:has_item?, is_map_key(actor.inventory, item)},
         %Character{name: subject_name} = subject <- party.directory[subject_id] do
      advantage =
        case party.proximity_map do
          %{^actor_name => leader, ^subject_name => leader} -> -2
          %{^subject_name => _leader} -> 0
        end

      case Character.attack(actor, item, subject, advantage) do
        {:ok, hit_roll, hit_mod, subject_ac, damage_roll, damage_mod, new_subject} ->
          {
            :ok,
            %Party{party | directory: Map.put(party.directory, subject_id, new_subject)},
            """
            *#{actor_id} rolled a #{hit_roll} #{Texts.modifier(hit_mod, "proficiency bonus")} = #{hit_roll + hit_mod} to hit, which beats #{subject}'s AC of #{subject_ac}!*\s\s
            *#{actor_id} rolled a #{damage_roll} #{Texts.modifier(damage_mod, "armor resist")} = #{Character.cur_hp(subject) - Character.cur_hp(new_subject)} damage!*\s\s
            "🎯#{verbiage} and left them with a gruesome wound!"
            """
          }

        {:miss, hit_roll, hit_mod, subject_ac} ->
          action_text =
            if hit_roll + hit_mod < subject_ac / 2 do
              "#{verbiage} and missed!"
            else
              "#{verbiage}, but the #{item.ammo} deflected off of their armor!"
            end

          {
            :ok,
            party,
            """
            *#{actor_id} rolled a #{hit_roll} #{Texts.modifier(hit_mod, "proficiency bonus")} = #{hit_roll + hit_mod} to hit, which lost to #{subject_name}'s AC of #{subject_ac}!*\s\s
            #{action_text}
            """
          }
      end
    else
      {:has_item?, false} ->
        {:invalid, "(You don't have a(n) '#{item}' in your inventory)"}
    end
  end

  defp consumable_action(%Party{} = party, actor_id, item, {present, past}) do
    case party.directory[actor_id] do
      %Character{inventory: %{^item => %Item{type: %Item.Consumable{effect: :nothing}}}} = actor ->
        {
          :ok,
          party,
          "#{actor.name} #{past} their #{item}. It didn't seem to do anything"
        }

      %Character{inventory: %{^item => %Item{type: %Item.Consumable{effect: {:health, hp}}}}} = actor ->
        char_updater = &(&1 |> Character.add_hp(hp) |> Character.dec_inventory_quantity(item))

        {
          :ok,
          %Party{party | directory: Map.update!(party.directory, actor_id, char_updater)},
          """
          *#{actor_id} regained #{hp}hp (@ #{Character.cur_hp(actor) + hp}hp total)*\s\s
          #{actor.name} #{past} their #{item} and feels much better.
          """
        }

      %Character{inventory: %{^item => %Item{}}} = actor ->
        {
          :ok,
          party,
          "#{actor.name} tries to #{present} their #{item}...(wtf?)"
        }

      %Character{inventory: inventory} when not is_map_key(inventory, item) ->
        {:invalid, "(You don't have a(n) '#{item}' in your inventory)"}
    end
  end
end
