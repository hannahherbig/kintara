#
# kintara: malkier xmpp server
# bin/kintara: startup routines, etc
#
# Copyright (c) 2004-2009 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

# Import required Ruby modules
%w(logger optparse yaml).each { |m| require m }

# XXX - Since IDN doesn't work in 1.9 yet, we're going to just make sure the
# qualifying strings are set to be encoded as UTF-8.

# XXX - for quick reference
#
# {"domains"=>"malkier.net, optera.org", "logging"=>{"enabled"=>true,
#  "general"=>"var/log/general.log", "c2s"=>"var/log/c2s.log",
#  "s2s"=>"var/log/s2s.log"}, "listen"=>{"c2s"=>"*:5222", "s2s"=>"*:5269",
#  "certificate"=>"etc/cert.pem"}, "authorize"=>{"matches"=>"(.*)"},
#  "deny"=>nil, "operators"=>{"rakaur"=>"announce"}

# The main application class.
class Kintara
    # Project name.
    ME = 'kintara'

    # Version number.
    V_MAJOR  = 0
    V_MINOR  = 1
    V_TINY   = 0

    VERSION  = "#{V_MAJOR}.#{V_MINOR}.#{V_TINY}"

    # Configuration data.
    @@config = nil

    #
    # Create a new +Kintara+ object, which starts and runs the entire
    # application. Everything starts and ends here.
    #
    # return:: self
    #
    def initialize
        puts "#{ME}: version #{VERSION} [#{RUBY_PLATFORM}]"

        # Check to see if we're running on a decent version of ruby.
        if RUBY_VERSION < '1.8.6'
            puts "#{ME}: requires at least ruby 1.8.6"
            puts "#{ME}: you have #{RUBY_VERSION}"
            abort
        elsif RUBY_VERSION < '1.9.1'
            puts "#{ME}: supports ruby 1.9 (much faster)"
            puts "#{ME}: you have #{RUBY_VERSION}"
        end

        # Check to see if we're running as root.
        if Process.euid == 0
            puts "#{ME}: refuses to run as root"
            abort
        end

        # Some defaults for state.
        logging  = true
        debug    = false
        willfork = RUBY_PLATFORM =~ /win32/i ? false : true
        wd       = Dir.getwd

        # Do command-line options.
        opts = OptionParser.new

        dd = 'Enable debug logging.'
        hd = 'Display usage information.'
        nd = 'Do not fork into the background.'
        qd = 'Disable regular logging.'
        vd = 'Display version information.'

        opts.on('-d', '--debug',   dd) { debug    = true  }
        opts.on('-h', '--help',    hd) { puts opts; abort }
        opts.on('-n', '--no-fork', nd) { willfork = false }
        opts.on('-q', '--quiet',   qd) { logging  = false }
        opts.on('-v', '--version', vd) { abort            }

        begin
            opts.parse(*ARGV)
        rescue OptionParser::ParseError => err
            puts err, opts
            abort
        end

        # Signal handlers.
        trap(:INT)   { kin_exit }
        trap(:PIPE)  { :SIG_IGN }
        trap(:CHLD)  { :SIG_IGN }
        trap(:WINCH) { :SIG_IGN }
        trap(:TTIN)  { :SIG_IGN }
        trap(:TTOU)  { :SIG_IGN }
        trap(:TSTP)  { :SIG_IGN }

        # Load configuration file.
        begin
            @@config = YAML.load_file('etc/config.yml')
        rescue Exception => e
            puts '----------------------------'
            puts "#{ME}: configure error: #{e}"
            puts '----------------------------'
            abort
        end

        if debug
            puts "#{ME}: warning: debug mode enabled"
            puts "#{ME}: warning: all streams will be logged in the clear!"
        end

        # Check to see if we're already running.
        if File.exists?('var/kintara.pid')
            curpid = nil
            File.open('var/kintara.pid', 'r') { |f| curpid = f.read.chomp.to_i }

            begin
                Process.kill(0, curpid)
            rescue Errno::ESRCH
                File.delete('var/kintara.pid')
            else
                puts "#{ME}: daemon is already running"
                abort
            end
        end

        # Fork into the background
        if willfork
            begin
                pid = fork
            rescue Exception => e
                puts "#{ME}: cannot fork into the background"
                abort
            end

            # This is the child process.
            unless pid
                Dir.chdir(wd)
                File.umask(0)
            else # This is the parent process.
                puts "#{ME}: pid #{pid}"
                puts "#{ME}: running in background mode from #{Dir.getwd}"
                abort
            end

            $stdin.close
            $stdout.close
            $stderr.close
        else
            puts "#{ME}: pid #{Process.pid}"
            puts "#{ME}: running in foreground mode from #{Dir.getwd}"
        end

        # Write the PID file.
        Dir.mkdir('var') unless File.exists?('var')
        File.open('var/kintara.pid', 'w') { |f| f.puts(pid) }

        kin_exit

        self
    end

    ######
    public
    ######

    def config
        @@config
    end

    #######
    private
    #######

    def kin_exit
        File.delete('var/kintara.pid')
        exit
    end
end
