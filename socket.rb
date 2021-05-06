category "Docker Nginx"

sample_interval 10

describe_samples do
  aggregation_dimensions = {
    group: ENV['CS_AGGREGATION_GROUP'],
  }.compact

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
