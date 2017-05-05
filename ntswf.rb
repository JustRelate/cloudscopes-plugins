require 'aws-sdk'
require 'yaml'
require 'json'

UNIT_PATTERN_TO_APP = {
  /scrivitocom/ => "dashboard",
  /dashboard/ => "dashboard",
  /crm/ => "crm",
  /console/ => "console",
  /scriv.*cms/ => "backend",
  /demo/ => "demo",
  /cms/ => "cms",
}

class LastEvent
  class Identity < Struct.new(:container_id, :pid, :stack_id)
    class << self
      def for(event)
        attributes = event.decision_task_started_event_attributes ||
            event.activity_task_started_event_attributes
        identity = attributes && attributes[:identity] or
            raise "Missing identity in event: #{event.to_h}"
        container_id, pid, stack_id = identity.split(":")
        raise "Unexpected identity #{identity} - cannot split by :" unless pid
        raise "Unexpected pid #{pid} from identity #{identity}" unless pid.to_i.to_s == pid
        new(container_id, pid, stack_id)
      end

      def container_ids
        @container_ids ||= `sudo /usr/bin/docker ps --filter name=background-worker --quiet`.split
      end
    end
  end

  def initialize(execution, swf, domain, reporter)
    @execution = execution
    @swf = swf
    @domain = domain
    @reporter = reporter
  end

  def event_type
    event.event_type
  end

  def zombie?
    if aws_expects_running_here? && !running?
      # the inspected event is still the last event of the execution
      if event.id == current_last_event_of_execution.id
        reporter.log.info("Zombie | #{log_data.join(" | ")}")
        true
      end
    end
  end

  def running?
    system("sudo /usr/bin/docker exec #{identity.container_id} test -e /proc/#{identity.pid}")
  end

  def computed_app_name
    @computed_app_name = compute_app_name unless defined? @computed_app_name
    @computed_app_name
  end

  def app_name
    computed_app_name || "unknown"
  end

  def remember_waiting
    reporter.remember_waiting(app_name, log_data(false).join(" | "))
  end

  private

  attr_reader :execution, :swf, :domain, :reporter

  def history_events
    @history_events ||= swf.get_workflow_execution_history(
      domain: domain,
      execution: execution,
    ).events
  end

  def first_event_attributes
    @first_event_attributes ||= history_events.first.workflow_execution_started_event_attributes
  end

  def compute_app_name
    input_as_json = first_event_attributes[:input]
    if input_as_json
      input = JSON(input_as_json)
      unit = input["unit"]
      match = UNIT_PATTERN_TO_APP.keys.detect {|pattern, app| unit =~ pattern}
      if match
        UNIT_PATTERN_TO_APP[match]
      end
    end
  end

  def aws_expects_running_here?
    Identity.container_ids.include?(identity.container_id)
  end

  def event
    @event ||= current_last_event_of_execution
  end

  def current_last_event_of_execution
    history_events.last
  end

  def identity
    @identity ||= Identity.for(event)
  end

  def log_data(zombie = true)
    d = []
    if zombie
      d << "identity: #{identity.to_a}" # to_h prefered - Ruby 2.x
      d << "app: #{app_name}"
      d << "type: #{event_type}"
    end
    d << "execution: Rails.application.workflow.ntswf.domain.workflow_executions.at"\
    "(\"#{execution.workflow_id}\", \"#{execution.run_id}\")"
    d << "details: #{first_event_attributes.to_h}"
    d
  end
end

def waiting
  @waiting ||= Hash.new {|h, k| h[k] = []}
end

def remember_waiting(app, message)
  waiting[app] << message
end

def log_waiting(limit)
  waiting.each do |app, messages|
    next if messages.count < limit
    prefix = "[Waiting]"
    continued = "\n ...      "
    log.info(
        "#{prefix} app: #{app} | count: #{messages.count}#{continued}#{messages.join(continued)}")
  end
end

def app_name(event)
  app_name = event.computed_app_name
  case app_name
  when nil
    "unknown"
  when *applications
    app_name
  else
    "other"
  end
end

def metric_name(key)
  "#{key}_tasks"
end

def swf
  @swf ||= Aws::SWF::Client.new(region: 'eu-west-1')
end

def domain
  @domain ||= ENV['CS_NTSWF_DOMAIN']
end

def open_executions
  swf.list_open_workflow_executions(
    domain: domain,
    start_time_filter: {oldest_date: Time.now - 86400 * 365 },
  ).execution_infos
end

def applications
  @applications ||= ENV['CS_NTSWF_APPLICATIONS'].split(/[ ,]+/)
end

def statistics
  @statistics ||= begin
    statistics = {}
    (applications + %w[other unknown]).each do |app|
      statistics[app] = {}
      %w[open waiting waiting_decision waiting_activity zombie].each do |type|
        statistics[app][metric_name(type)] = 0
      end
    end
    statistics
  end
end


category "NTSWF"

describe_samples do
  if domain
    open_executions.each do |execution_info|
      last_event = LastEvent.new(execution_info.execution, swf, domain, self)

      app = app_name(last_event)
      statistics[app][metric_name("open")] += 1
      case last_event.event_type
      when "DecisionTaskScheduled"
        last_event.remember_waiting
        statistics[app][metric_name("waiting")] += 1
        statistics[app][metric_name("waiting_decision")] += 1
      when "ActivityTaskScheduled"
        last_event.remember_waiting
        statisticsapp[metric_name("waiting")] += 1
        statistics[metric_name("waiting_activity")] += 1
      when "ActivityTaskStarted", "DecisionTaskStarted"
        statistics[app][metric_name("zombie")] += 1 if last_event.zombie?
      end
    end
    log_waiting(3)
    statistics.each do |app, metrics|
      dimensions = {AppName: app}
      metrics.each do |name, value|
        sample(name: name, value: value, dimensions: dimensions)
      end
    end
  end
end
