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
    VERSION  = '1.0a'

    # Codename for major version.
    CODENAME = 'synapse'

    #
    # Create a new +Kintara+ object, which starts and runs the entire
    # application. Everything starts and ends here.
    #
    # return:: self
    #
    def initialize
        puts "#{ME}: version #{CODENAME}-#{VERSION} [#{RUBY_PLATFORM}]"

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

            # XXX - write pid/check if running

            $stdin.close
            $stdout.close
            $stderr.close
        else
            puts "#{ME}: pid #{Process.pid}"
            puts "#{ME}: running in foreground mode from #{Dir.getwd}"
        end

        self
    end
end
