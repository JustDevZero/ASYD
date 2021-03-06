module Dmon
  DAEMONS = ['monitoring', 'awal', 'dmon']

  def self.init
    DAEMONS.each do |daemon|
      start(daemon)
    end if File.directory? 'data'
  end

  def self.handler
    Signal.trap("TERM") {
      DAEMONS.each do |daemon|
        stop(daemon) unless daemon == 'dmon'
      end
      exit
    }

    while true
      sleep 63
      DAEMONS.each do |daemon|
        start(daemon) unless check(daemon)
      end
      FileUtils.touch 'data/.dmon.pid'
      Net::HTTP.get_response(URI.parse("http://localhost:#{$PORT}/api/ping"))
    end
  end

  def self.setpid(daemon, pid)
    pidfile = open('data/.'+daemon+'.pid', 'w')
    pidfile.write(pid)
    pidfile.close
  end

  def self.getpid(daemon)
    if File.exist?('data/.'+daemon+'.pid')
      pid = File.read('data/.'+daemon+'.pid')
      if pid.nil? || pid.empty?
        return 0
      else
        return pid.to_i
      end
    else
      return 0
    end
  end

  def self.check(daemon)
    pid = getpid(daemon)
    if Misc::checkpid(pid)
      if File.mtime('data/.'+daemon+'.pid') < (Time.now - 2*60) # if the daemon was inactive for 2 minutes
        return false
      else
        return true
      end
    else
      return false
    end
  end

  def self.stop(daemon)
    pid = getpid(daemon)
    Process.kill("TERM", pid) if pid > 0 && Misc::checkpid(pid)
  end

  def self.start(daemon)
    stop(daemon)  # Ensure it is not running

    if daemon == 'monitoring'
      # monitoring on the background
      Spork.spork do
        Process.setsid
        pid = Spork.spork do
          $0='ASYD Monitoring Daemon'
          # STDIN.reopen '/dev/null'
          # STDOUT.reopen '/dev/null', 'a'
          # STDERR.reopen STDOUT
          Monitoring.background
        end
        setpid(daemon, pid)
        exit
      end
    elsif daemon == 'awal'
      # check for checkpoints
      Spork.spork do
        Process.setsid
        pid = Spork.spork do
          $0='ASYD WAL Daemon'
          # STDIN.reopen '/dev/null'
          # STDOUT.reopen '/dev/null', 'a'
          # STDERR.reopen STDOUT
          Awal::should_checkpoint?
        end
        setpid(daemon, pid)
        exit
      end
    elsif daemon == 'dmon'
      # The Dmon-handler
      Spork.spork do
        Process.setsid
        pid = Spork.spork do
          $0='ASYD Daemon Manager'
          # STDIN.reopen '/dev/null'
          # STDOUT.reopen '/dev/null', 'a'
          # STDERR.reopen STDOUT
          Dmon::handler
        end
        setpid(daemon, pid)
        exit
      end
    end
  end
end
