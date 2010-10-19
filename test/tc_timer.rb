#
# kintara: malkier xmpp server
# test/tc_timer.rb: timer unit testing
#
# Copyright (c) 2003-2010 Eric Will <rakaur@malkier.net>
#
# encoding: utf-8

require 'test/unit'
require 'kintara/timer.rb'

class TestTimer < Test::Unit::TestCase
    @ts = nil
    @tn = nil

    def test_001_timer
        @ts = Time.now.to_f

        assert_nothing_raised { Timer.after(1) { timer_callback_1 } }
        assert_nothing_raised { Timer.after(2) { timer_callback_2 } }

        Thread.list.each { |t| t.join unless t == Thread.main }
    end

    def timer_callback_1
        @tn   = Time.now.to_f
        delta = @tn - @ts

        assert(delta >= 1)
    end

    def timer_callback_2
        @tn   = Time.now.to_f
        delta = @tn - @ts

        assert(delta >= 2)
    end
end

