defmodule Extractions do

  @format ~r[(?<start_hour>\d{2}):(?<start_minute>\d{2})-(?<end_hour>\d{2}):(?<end_minute>\d{2})]

  def start do
    start_date = Calendar.DateTime.from_erl!({{2020, 1, 25},{0, 29, 10}}, "Etc/UTC", {123456, 6}) #|> Calendar.DateTime.shift_zone!("Europe/Dublin")
    end_date = Calendar.DateTime.from_erl!({{2020, 2, 2},{0, 29, 10}}, "Etc/UTC", {123456, 6}) #|> Calendar.DateTime.shift_zone!("Europe/Dublin")
    schedule = %{
      "Friday" => ["00:00-23:59"],
      "Monday" => ["00:00-23:59"],
      "Saturday" => ["00:00-23:59"],
      "Sunday" => ["00:00-23:59"],
      "Thursday" => ["00:00-23:59"],
      "Tuesday" => ["00:00-23:59"],
      "Wednesday" => ["00:00-23:59"]
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
      #Put skip empty filter here as well.

    valid_dates =
      all_days
      |> get_date_pairs(camera_exid, schedule)
      |> Enum.map(&handle_pair(&1, interval))
  end

  defp handle_pair(%{starting: starting, ending: ending}, interval) do
    {:ok, after_seconds, 0, :after} = Calendar.DateTime.diff(ending, starting)
    chunk = ((after_seconds / interval) + 1) |> Float.ceil |> trunc
    Stream.iterate(starting, &(Calendar.DateTime.add!(&1, interval)))
    |> Enum.take(chunk)
  end

  def get_expected_count(dates, interval) do
    Enum.reduce(dates, 0, fn date_pair, count ->
      %{starting: starting, ending: ending} = date_pair
      {:ok, after_seconds, 0, :after} = Calendar.DateTime.diff(ending, starting)
      count + (after_seconds / interval)
    end) |> Float.ceil
  end

  defp get_date_pairs(dates, camera_exid, schedule) do
    dates
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
end
