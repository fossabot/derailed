# Copyright (C) 2024 V.J. De Chico
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

defmodule Derailed.Session do
  use GenServer

  def start_link(id) do
    GenServer.start_link(__MODULE__, id)
  end

  def init({id, user_id, ws_pid}) do
    {_, result} =
      Postgrex.prepare_execute!(
        :db,
        "get_user_account_session_genserver",
        "SELECT * FROM accounts WHERE id = $1;",
        [user_id]
      )

    {:ok, account} = Derailed.DB.map(result)
    {_, account} = Map.pop!(account, "password")

    {_, result} =
      Postgrex.prepare_execute!(
        :db,
        "get_user_actor_session_genserver",
        "SELECT * FROM actors WHERE id = $1;",
        [user_id]
      )

    {:ok, actor} = Derailed.DB.map(result)

    # TODO: relationships
    # {_, result} =
    #  Postgrex.prepare_execute!(
    #    :db,
    #    "get_relationships_session_genserver",
    #    "SELECT * FROM relationships WHERE user_id = $1;",
    #    [user_id]
    #  )

    # {:ok, relationships} = Derailed.DB.maps(result)

    {_, result} =
      Postgrex.prepare_execute!(
        :db,
        "get_guilds_session_genserver",
        "SELECT * FROM guilds WHERE id IN (SELECT guild_id FROM guild_members WHERE user_id = $1);",
        [user_id]
      )

    {:ok, guilds} = Derailed.DB.maps(result)

    guild_pids =
      Enum.map(guilds, fn g ->
        {:ok, pid} = GenRegistry.lookup_or_start(Derailed.Guild, g["id"], [{g["id"], g}])
        pid
      end)

    guild_refs = Enum.map(guild_pids, fn c -> Process.monitor(c) end)

    {:ok,
     %{
       id: id,
       account_data: account,
       actor_data: actor,
       # relationship_data: relationships,
       guild_data: guilds,
       guild_pids: guild_pids,
       guild_refs: guild_refs,
       ws_pid: ws_pid,
       ws_ref: Process.monitor(ws_pid)
     }}
  end

  @spec send_ready(pid()) :: :ok
  def send_ready(pid) do
    GenServer.cast(pid, :send_ready)
  end

  def handle_cast(:send_ready, state) do
    Manifold.send(state[:ws_pid], {
      :event,
      "READY",
      %{
        relationships: state[:relationship_data],
        user: state[:user_data],
        guilds: state[:guild_data]
      }
    })

    {:noreply, state}
  end

  def handle_info({:event, :guild, type, data}, state) do
    Manifold.send(state[:ws_pid], {:event, type, data})
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    if ref in state[:guild_refs] do
      # TODO: handle
      {:stop, :laziness, state}
    else
      # TODO: resume
      {:stop, :ws_down, state}
    end
  end
end
