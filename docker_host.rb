category "Docker Host"

describe_samples do
  processes = process.list.sort_by(&:mem_usage_rss)
  dimensions = {InstanceId: ec2.instance_id}
  sample(
    name: "Load Per CPU",
    value: 100 * system.loadavg5 / system.cpucount,
    unit: "Percent",
    dimensions: dimensions,
  )
  sample(
    name: "Pending IO",
    value: system.iostat[8],
    unit: "Count",
    dimensions: dimensions,
  )
  sample(
    name: "Memory Utilization",
    value: 100 * memory.MemUsed / memory.MemTotal,
    unit: "Percent",
    dimensions: dimensions
  )
  sample(
    name: "Largest Process Size",
    value: processes.last.mem_usage_rss / 1024**2,
    unit: "Megabytes",
    dimensions: dimensions,
  )
  {
    "Background" => "B|",
    "Web" => "unicorn_rails ",
  }.each do |type, prefix|
    if process = processes.select {|p| p.cmdline.start_with?(prefix) }.last
      sample(
        name: "Largest #{type} Worker Size",
        value: process.mem_usage_rss / 1024**2,
        unit: "Megabytes",
        dimensions: dimensions,
      )
    end
  end
end
