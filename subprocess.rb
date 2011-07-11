class Subprocess
  POLL_INTERVAL = 0.1
  attr_reader :pid, :stdin, :stdout, :stderr, :start_time, :end_time, :duration
  attr_accessor :on_exit

  class << self
    def open(*arguments)
      subprocess = new(*arguments)

      if block_given?
        yield subprocess
        subprocess.detach
        subprocess.close
      end

      subprocess
    end
  end

  def initialize(*arguments)
    @stdin_r, @stdin = IO.pipe
    @stdout, @stdout_w = IO.pipe
    @stderr, @stderr_w = IO.pipe

    options = arguments.last.is_a?(Hash) ? arguments.pop : {}

    @on_exit = options.delete(:on_exit)
    @in = options.delete(:stdin) || @stdin_r
    @out = options.delete(:stdout) || @stdout_w
    @err = options.delete(:stderr) || @stderr_w

    options[:in] = @in unless @in == "inherit"
    options[:out] = @out unless @out == "inherit"
    options[:err] = @err unless @err == "inherit"

    # Support Tempfile and others
    [:in, :out, :err].each { |o|
	options[o].open if options[o].respond_to? :open
	options[o].sync = true if options[o].respond_to? :sync
    	options[o] = options[o].to_io if options[o].respond_to? :to_io
    }

    @start_time = Time.now()
    @pid = Process.spawn(*(arguments << options))

    previous_trap = trap("CHLD") do |a|
      if a == 17 && pid == @pid
        @end_time = Time.now()
        @duration = @end_time-@start_time
        # @total_subprocess_cpu_time = Process.times.c[us]time
        exited?
        close
        if @on_exit.respond_to?(:call)
          @on_exit.call(self)
        end
      end

      previous_trap.call(a) if previous_trap
    end
  end

  def detach
    Process.detach(pid)
  end

  def stop(timeout = 3)
    term
    unless poll_for_exit(timeout)
      # Try to kill if term signal failed
      kill
      poll_for_exit(timeout)
    end
    @exit_code if exited?
  rescue Errno::ECHILD, Errno::ESRCH
    # handle race condition where process dies between timeout
    # and send_kill
    @exit_code if exited?
  end

  def term
    signal 'TERM'
  end

  def kill
    signal 'KILL'
  end

  def signal(signal)
    Process.kill(signal, pid)
    @exit_code if exited?
  end

  def running?
      !exited?
  end

  def exited?
    return true if @exit_code
    
    pid, status = Process.waitpid2(@pid, ::Process::WNOHANG)
    if pid
      @exit_code = status.exitstatus || status.termsig
    end
    
    !!pid
  rescue Errno::ECHILD, Errno::ESRCH
    nil 
  end

  # Return status code if exits or Nil if doesn't
  def poll_for_exit(timeout)
      end_time = Time.now + timeout
      until (ok = exited?) || Time.now > end_time
        sleep POLL_INTERVAL
      end
      return @exit_code
  end

  def wait(flags = 0)
    @status ||= begin
      _, status = Process.wait2(pid, flags)
    end
  end

  private

  def close
    # [@stdin_r, @stdin, @stdout, @stdout_w, @stderr, @stderr_w].each(&:close)
    [@stdin_r, @stdin, @stdout_w, @stderr, @stderr_w].each(&:close)
  end

  def status(flags = 0)
    wait(flags | Process::WNOHANG)
  end

end
