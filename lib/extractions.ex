defmodule Extractions do

  @format ~r[(?<start_hour>\d{2}):(?<start_minute>\d{2})-(?<end_hour>\d{2}):(?<end_minute>\d{2})]

  def start do
    start_date = Calendar.DateTime.from_erl!({{2020, 1, 25},{0, 29, 10}}, "Etc/UTC", {123456, 6}) #|> Calendar.DateTime.shift_zone!("Europe/Dublin")
    end_date = Calendar.DateTime.from_erl!({{2020, 2, 2},{0, 29, 10}}, "Etc/UTC", {123456, 6}) #|> Calendar.DateTime.shift_zone!("Europe/Dublin")

    schedule = %{
      "Friday" => ["08:00-18:00"],
      "Monday" => ["08:00-18:00"],
      "Saturday" => [],
      "Sunday" => [],
      "Thursday" => ["08:00-18:00"],
      "Tuesday" => ["08:00-18:00"],
      "Wednesday" => ["08:00-18:00"]
    }
    |> Enum.filter(fn {_, v} -> length(v) != 0 end)
    |> Enum.into(%{})

    days =
      schedule
      |> Enum.map(fn(sc) ->
        {day, hours} = sc
        if length(hours) != 0, do: day
      end) |> Enum.filter(& !is_nil(&1))

    camera_exid = "waxie-jolxd"

    interval = 1200

    all_days =
      Calendar.Date.days_after_until(start_date, end_date, true)
      |> Enum.filter(fn(day) ->
        Enum.member?(days, day |> Calendar.Strftime.strftime!("%A"))
      end)

    valid_dates =
      all_days
      |> get_date_pairs(camera_exid, schedule)

    {get_expected_count} =
      Enum.reduce(valid_dates, {0}, fn date_pair, {count} ->
        %{starting: starting, ending: ending} = date_pair
        {:ok, after_seconds, 0, :after} = Calendar.DateTime.diff(ending, starting)
        {count + (after_seconds / interval)}
      end)
  end

  defp get_date_pairs(dates, camera_exid, schedule) do
    dates
    # |> Enum.filter(fn date ->
    #   request_from_seaweedfs("http://localhost:8888/#{camera_exid}/snapshots/recordings/#{strft_date(date, "%Y")}/#{strft_date(date, "%m")}/#{strft_date(date, "%d")}/", "Entries", "FullPath") != []
    # end)
    |> Enum.map(fn date ->
      schedule[Calendar.Strftime.strftime!(date, "%A")]
      |> get_head_tail
      |> Enum.map(fn timings -> Regex.named_captures(@format, timings |> List.first) end)
      |> Enum.map(fn schedule_time ->
        Map.merge(
          %{
            "year" => strft_date(date, "%Y"),
            "month" => strft_date(date, "%m"),
            "day" => strft_date(date, "%d")
          },
          schedule_time
        )
      end)
    end)
    |> List.flatten
    |> Enum.map(fn date_tuple ->
      {starting, ending} = parse_schedule_times(date_tuple)
      %{
        starting: Calendar.DateTime.from_erl!(starting, "Etc/UTC", {123456, 6}) |> shift_zone,
        ending: Calendar.DateTime.from_erl!(ending, "Etc/UTC", {123456, 6}) |> shift_zone
      }
    end)
  end

  defp strft_date(date, pattern), do: Calendar.Strftime.strftime!(date, pattern)

  defp get_base_name(list, "Entries", "FullPath"), do: list |> Path.basename
  defp get_base_name(list, _, _), do: list

  def request_from_seaweedfs(url, type, attribute) do
    hackney = []
    with {:ok, response} <- HTTPoison.get(url, ["Accept": "application/json"], hackney: hackney),
         %HTTPoison.Response{status_code: 200, body: body} <- response,
         {:ok, data} <- Jason.decode(body),
         true <- is_list(data[type]) do
      Enum.map(data[type], fn(item) -> item[attribute] |> get_base_name(type, attribute) end)
    else
      _ -> []
    end
  end

  defp shift_zone(date, timezone \\ "Europe/Dublin") do
    date |> Calendar.DateTime.shift_zone!(timezone)
  end

  defp parse_schedule_times(%{"end_hour" => end_hour, "end_minute" => end_minute, "start_hour" => start_hour, "start_minute" => start_minute, "year" => year, "month" => month, "day" => day}) do
    {{{String.to_integer(year), String.to_integer(month), String.to_integer(day)}, {String.to_integer(start_hour), String.to_integer(start_minute), 0}}, {{String.to_integer(year), String.to_integer(month), String.to_integer(day)}, {String.to_integer(end_hour), String.to_integer(end_minute), 0}}}
  end

  def get_head_tail([]), do: []
  def get_head_tail(nil), do: []
  def get_head_tail([head|tail]) do
    [[head]|get_head_tail(tail)]
  end

  def ambiguous_handle(value) do
    case value do
      {:ok, datetime} -> datetime
      {:ambiguous, datetime} -> datetime.possible_date_times |> hd
    end
  end
end
