require 'net/http'

attr_accessor :last_requests, :last_request_time

category "Docker Nginx"

sample_interval 10

describe_samples do
  aggregation_dimensions = {
    group: ENV['CS_AGGREGATION_GROUP'],
  }.compact

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
end
