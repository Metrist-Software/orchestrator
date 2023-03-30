defmodule Orchestrator.PingInvokerTest do
  use ExUnit.Case, async: true

  alias Orchestrator.PingInvoker

  test "Parsing valid iputils ping output" do
    output = "PING amazonaws.com (72.21.206.80) 56(84) bytes of data.\n64 bytes from 206-80.amazon.com (72.21.206.80): icmp_seq=1 ttl=223 time=49.7 ms\n64 bytes from 206-80.amazon.com (72.21.206.80): icmp_seq=2 ttl=223 time=59.3 ms\n64 bytes from 206-80.amazon.com (72.21.206.80): icmp_seq=3 ttl=223 time=46.8 ms\n64 bytes from 206-80.amazon.com (72.21.206.80): icmp_seq=4 ttl=223 time=55.6 ms\n64 bytes from 206-80.amazon.com (72.21.206.80): icmp_seq=5 ttl=223 time=54.5 ms\n\n--- amazonaws.com ping statistics ---\n5 packets transmitted, 5 received, 0% packet loss, time 4005ms\nrtt min/avg/max/mdev = 46.799/53.179/59.289/4.423 ms\n"

    {:ok, 53.179} = PingInvoker.parse_output(output)
  end

  test "Parsing valid BusyBox ping output" do
    output = "PING amazonaws.com (72.21.206.80): 56 data bytes\n64 bytes from 72.21.206.80: seq=0 ttl=224 time=49.578 ms\n64 bytes from 72.21.206.80: seq=1 ttl=224 time=48.962 ms\n64 bytes from 72.21.206.80: seq=2 ttl=224 time=48.183 ms\n\n--- amazonaws.com ping statistics ---\n3 packets transmitted, 3 packets received, 0% packet loss\nround-trip min/avg/max = 48.183/48.907/49.578 ms\n"

    {:ok, 48.907} = PingInvoker.parse_output(output)
  end

  test "Invalid output returns error" do
    output = "You wanted to ping\nbut there is no ping\nWe're noping the ping\n"

    :error = PingInvoker.parse_output(output)
  end
end
