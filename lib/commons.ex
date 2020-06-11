defmodule Commons do

  def get_head_tail([]), do: []
  def get_head_tail(nil), do: []
  def get_head_tail([head|tail]) do
    [[head]|get_head_tail(tail)]
  end

  def intervaling(0), do: 1
  def intervaling(n), do: n

  def save_current_jpeg_time(url, path, :v2) do
    File.write!("#{path}CURRENT", url <> "\n", [:append])
  end
end
