category "Docker Host"

describe_samples do
  processes = process.list.sort_by(&:mem_usage_rss)
  data = [
    ["Load Per CPU", "Percent", 100 * system.loadavg5 / system.cpucount],
    ["Pending I/O", "Count", system.iostat[8]],
    ["Memory Utilization", "Percent", 100 * memory.MemUsed / memory.MemTotal],
    ["Largest Process Size", "Megabytes", processes.last.mem_usage_rss / 1024**2],
  ]
  {
    "Background" => "B|",
    "Web" => "unicorn_rails ",
  }.each do |type, prefix|
    if process = processes.select {|p| p.cmdline.start_with?(prefix) }.last
      data << ["Largest #{type} Worker Size", "Megabytes", process.mem_usage_rss / 1024**2]
    end
  end

  dimensions = {InstanceId: ec2.instance_id}
  data.each do |name, unit, value|
    sample(name: name, unit: unit, value: value, dimensions: {})
    sample(name: name, unit: unit, value: value, dimensions: dimensions)
  end
end
