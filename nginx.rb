require 'net/http'

attr_accessor :last_requests, :last_request_time

category "Docker Nginx"

sample_interval 10

describe_samples do
  total, reading, writing, waiting, requests = nil
  request_time = Time.now

  response = Net::HTTP.get_response(URI("http://127.0.0.1/nginx_status"))
  raise "Failed to get Nginx status: #{response.code} #{response.body}" unless response.code == "200"

  response.body.split("\n").each do |line|
    total = Regexp.last_match(1).to_i if line =~ /^Active connections:\s+(\d+)/
    if line =~ /^Reading:\s+(\d+).*Writing:\s+(\d+).*Waiting:\s+(\d+)/
      reading = Regexp.last_match(1).to_i
      writing = Regexp.last_match(2).to_i
      waiting = Regexp.last_match(3).to_i
    end
    requests = Regexp.last_match(3).to_i if line =~ /^\s+(\d+)\s+(\d+)\s+(\d+)/
  end

  requests_per_second = (requests - last_requests) / (request_time - last_request_time) if last_requests
  self.last_requests = requests
  self.last_request_time = request_time

  rack_active = rack_queued = 0
  `cat /proc/net/unix`.split("\n").each do |line|
    next unless line =~ %r{/(unicorn|puma).sock$}

    _, _, _, _, _, _, inode, = line.split(' ')
    if inode == "0"
      rack_queued += 1
    else
      rack_active += 1
    end
  end

  aggregation_dimensions = {}
  if (aggregation_group = ENV['CS_AGGREGATION_GROUP'])
    aggregation_dimensions[:group] = aggregation_group
  end
  [
    ["Active Connections", total],
    ["Keep-Alive Connections", waiting],
    ["Reading Connections", reading],
    ["Writing Connections", writing],
    ["Requests Handled", requests],
    ["Request Throughput", requests_per_second, "Count/Second"]
  ].each do |(name, value, unit)|
    sample(
      name: name,
      value: value,
      unit: unit || "Count",
      aggregate: aggregation_dimensions,
      dimensions: {
        ClusterName: ec2.ecs_cluster,
        Task: ec2.ecs_task,
      }
    )
  end

  [
    ["Active Rack Connections", rack_active],
    ["Queued Rack Connections", rack_queued]
  ].each do |(name, value)|
    sample(
      name: name,
      value: value,
      unit: "Count",
      storage_resolution: 1,
      aggregate: aggregation_dimensions,
      dimensions: {
        ClusterName: ec2.ecs_cluster,
      }
    )
  end
end
