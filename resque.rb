require 'resque'
require 'resque-scheduler'

category "Resque"

Resque.redis = Redis.new

describe_samples do
  info = ::Resque.info
  queue_sizes = ::Resque.queue_sizes
  delayed = ::Resque.delayed_queue_schedule_size

  sample(name: "Working", unit: "Count", value: info[:working])
  sample(name: "Pending", unit: "Count", value: info[:pending])
  sample(name: "Workers", unit: "Count", value: info[:workers])

  queue_sizes.each do |name, size|
    sample(dimensions: {QueueName: name}, name: "Size", unit: "Count", value: size)
  end

  sample(name: "Delayed", unit: "Count", value: delayed)
end
