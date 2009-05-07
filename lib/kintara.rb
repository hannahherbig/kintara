#
# kintara: malkier xmpp server
# bin/kintara: startup routines, etc
#
# Copyright (c) 2004-2009 Eric Will <rakaur@malkier.net>
#

# Import required Ruby modules
%w(logger optparse).each { |m| require m }

# The main application class.
class Kintara
    # Project name.
    ME       = 'kintara'

    # Version number.
    V_MAJOR  = 0
    V_MINOR  = 1
    V_TINY   = 0
    MODIFIER = 'alpha'

    VERSION  = "#{V_MAJOR}.#{V_MINOR}.#{V_TINY}-#{MODIFIER}"

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
        trap(:INT)   { rhu_exit }
        trap(:PIPE)  { :SIG_IGN }
        trap(:CHLD)  { :SIG_IGN }
        trap(:WINCH) { :SIG_IGN }
        trap(:TTIN)  { :SIG_IGN }
        trap(:TTOU)  { :SIG_IGN }
        trap(:TSTP)  { :SIG_IGN }

        # Should probably do config stuff here - XXX

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
                # Write the PID file.
                Dir.mkdir('var') unless File.exists?('var')
                File.open('var/kintara.pid', 'w') { |f| f.puts(pid) }

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

        kin_exit

        self
    end

    #######
    private
    #######

    def kin_exit
        File.delete('var/kintara.pid')
        exit
    end
end
