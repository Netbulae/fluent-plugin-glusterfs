module Fluent
  require 'fluent/plugin/in_tail'
  require 'socket'

  class GlusterfsLogInput < Fluent::Plugin::TailInput
    Plugin.register_input("glusterfs_log", self)

    config_param :tag, :string, :default => nil
    config_param :gluster_log_level, :string, :default => 'TDINWECA'

    unless method_defined?(:log)
      define_method(:log) { $log }
    end

    def initialize
      super

      # NOTE: Here you can specify if output lines into the event stream
      #   that fluentd fails to parse or else. (:default => true)
      @handle_parse_failure ||= true

      # NOTE: Here you can configure field names of JSON.
      #   YOU SHOULD NOT SPECIFY EACH STRING AS NIL.
      field ||= {
          :date => 'date',
          :time => 'time',
          :time_usec => 'time_usec',
          :gluster_log_level => 'gluster_log_level',
          :source_file_name => 'source_file_name',
          :source_line => 'source_line',
          :function_name => 'function_name',
          :component_name => 'component_name',
          :message => 'message',
          :hostname => 'hostname'
      }

      # NOTE: Here you can set an optional hostname in string which is
      #   output into the JSON event logs. (:default => Socket.gethostname)
      @hostname ||= Socket.gethostname

      # NOTE: NEVER MODIFY FOLLOWING INITIALIZATIONS.
      @field = init_field(field)
      @time_format = init_time_format
      @regex = init_regex
    end

    # This method is called before starting.
    # 'conf' is a Hash that includes configuration parameters.
    # If the configuration is invalid, raise Fluent::ConfigError.
    def configure(conf)
      super

      unless @tag
        raise ConfigError, "'tag' option is required on glusterfs_log input"
      end

      @gluster_log_level = conf['gluster_log_level'] || 'TDINWECA'

      $log.debug "Glusterfs_log configuration: gluster_log_level = #{@gluster_log_level}"
    end

    def parse_line(line)
      time, record = super(line)

      begin
        return nil, nil unless line[0,1] == '['

        if @regex =~ line
          record = {
            @field[:date] => $1,
            @field[:time] => $2,
            @field[:time_usec] => $3,
            @field[:gluster_log_level] => $4,
            @field[:source_file_name] => $5,
            @field[:source_line] => $6,
            @field[:function_name] => $7,
            @field[:component_name] => $8,
            @field[:message] => $9,
            @field[:hostname] => @hostname
          }
          time = Time.strptime("#{record[@field[:date]]} #{record[@field[:time]]}", @time_format).to_i
        elsif @handle_parse_failure
          now = Time.now.utc
          datetime = now.to_s.split(' ')
          record = {
            @field[:date] => datetime[0],
            @field[:time] => datetime[1],
            @field[:gluster_log_level] => 'I',
            @field[:component_name] => 'fluent-plugin-glusterfs',
            @field[:message] => "Could not parse the line : #{line}",
            @field[:hostname] => @hostname
          }
          time = now.to_i
        end

        #$log.info "Glusterfs_log: time: #{time.inspect} record: #{record.inspect}"

        return time, record
      rescue => ex
        raise ex
      end
    end

    private

    def init_field(field)
      f = {}
      field.each do |k,v|
        f[k] = v.to_sym unless k.empty?
      end
      return f
    end

    def init_time_format
      '%Y-%m-%d %H:%M:%S'
    end

    def init_regex
      delimiter = '\[\]: '
      re = {
        :date => '\d{4}-[01]\d-[0-3]\d',
        :time => '[0-2]\d\:[0-5]\d\:[0-6]\d',
        :time_usec => '\d{6}',
        :gluster_log_level => "[#{@gluster_log_level}]",
        :source_file_name => "[^#{delimiter}]*",
        :source_line => '\d*',
        :function_name => "[^#{delimiter}]*",
        :component_name => "[^:]*",
        :message => '.*'
      }

      /\[(#{re[:date]}) (#{re[:time]}).(#{re[:time_usec]})\] (#{re[:gluster_log_level]}) \[(#{re[:source_file_name]}):(#{re[:source_line]}):(#{re[:function_name]})\] (#{re[:component_name]}): (#{re[:message]})/
    end

  end
end
