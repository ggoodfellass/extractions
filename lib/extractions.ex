defmodule Extractions do

  @format ~r[(?<start_hour>\d{2}):(?<start_minute>\d{2})-(?<end_hour>\d{2}):(?<end_minute>\d{2})]

  def start do
    start_date = Calendar.DateTime.from_erl!({{2019, 10, 2},{0, 29, 10}}, "Etc/UTC", {123456, 6}) #|> Calendar.DateTime.shift_zone!("Europe/Dublin")
    end_date = Calendar.DateTime.from_erl!({{2019, 12, 2},{0, 29, 10}}, "Etc/UTC", {123456, 6}) #|> Calendar.DateTime.shift_zone!("Europe/Dublin")

    interval = 1200

    all_days = Calendar.Date.days_after_until(start_date, end_date, true)
    schedule = %{
      "Friday" => ["08:00-18:00", "19:00-21:00"],
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

    valid_dates =
      Enum.filter(all_days, fn(day) ->
        Enum.member?(days, day |> Calendar.Strftime.strftime!("%A"))
      end)
      |> Enum.map(fn date ->
        schedule[Calendar.Strftime.strftime!(date, "%A")]
        |> get_head_tail
        |> Enum.map(fn timings -> Regex.named_captures(@format, timings |> List.first) end)
        |> Enum.map(fn schedule_time ->
          Map.merge(
            %{
              "year" => Calendar.Strftime.strftime!(date, "%Y"),
              "month" => Calendar.Strftime.strftime!(date, "%m"),
              "day" => Calendar.Strftime.strftime!(date, "%d")
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
