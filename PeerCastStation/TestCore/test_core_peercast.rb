# coding:utf-8
#
# PeerCastStation, a P2P streaming servent.
# Copyright (C) 2011 Ryuichi Sakamoto (kumaryu@kumaryu.net)
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
require 'test_core_common'
require 'shoulda/context'
require 'socket'

module TestCore
  class TC_CorePeerCast < Test::Unit::TestCase
    class MockYellowPageClientFactory
      include PeerCastStation::Core::IYellowPageClientFactory
      
      def name
        'mock_yp'
      end
      
      def protocol
        'mock'
      end
      
      def CheckURI(uri)
        true
      end
      
      def create(name, uri)
        MockYellowPageClient.new(name, uri, 'mock')
      end
    end

    class MockYellowPageClient
      include PeerCastStation::Core::IYellowPageClient
      def initialize(name, uri, protocol)
        @name = name
        @uri = uri
        @protocol = protocol
        @log = []
        @channels = []
      end
      attr_reader :name, :uri, :protocol, :log, :channels
      
      def find_tracker(channel_id)
        @log << [:find_tracker, channel_id]
        addr = System::Net::IPEndPoint.new(System::Net::IPAddress.parse('127.0.0.1'), 7147)
        System::Uri.new("mock://#{addr}")
      end
      
      def announce(channel)
        @log << [:announce, channel]
        @channels << channel
        nil
      end

      def restart_announce
        @log << [:restart_announce]
      end

      def stop_announce
        @log << [:stop_announce]
        @channels.clear
      end
    end

    def setup
    end
    
    def teardown
      @peercast.stop if @peercast
    end
    
    def test_construct
      @peercast = PeerCastStation::Core::PeerCast.new
      assert_not_nil(@peercast.access_controller)
      assert_equal(0, @peercast.yellow_pages.count)
      assert_equal(0, @peercast.yellow_page_factories.count)
      assert_equal(0, @peercast.source_stream_factories.count)
      assert_equal(0, @peercast.output_stream_factories.count)
      assert_equal(0, @peercast.content_reader_factories.count)
      assert_equal(0, @peercast.channels.count)
      
      assert_not_nil(@peercast.local_address)
      assert_nil(@peercast.global_address)
      assert_not_equal(System::Guid.empty, @peercast.SessionID)
      assert_not_equal(System::Guid.empty, @peercast.BroadcastID)
      assert_nil(@peercast.is_firewalled)
    end

    def test_find_listener_v4
      @peercast = PeerCastStation::Core::PeerCast.new
      @peercast.start_listen(
        System::Net::IPEndPoint.new(System::Net::IPAddress.Any, 7147),
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play |
        PeerCastStation::Core::OutputStreamType.interface,
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play |
        PeerCastStation::Core::OutputStreamType.interface)
      listener = @peercast.find_listener(
        System::Net::IPAddress.parse('192.168.1.1'),
        PeerCastStation::Core::OutputStreamType.relay)
      assert_kind_of(PeerCastStation::Core::OutputListener, listener)
    end
    
    def test_find_listener_v6
      @peercast = PeerCastStation::Core::PeerCast.new
      @peercast.start_listen(
        System::Net::IPEndPoint.new(System::Net::IPAddress.IPv6Any, 7147),
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play |
        PeerCastStation::Core::OutputStreamType.interface,
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play |
        PeerCastStation::Core::OutputStreamType.interface)
      listener = @peercast.find_listener(
        System::Net::IPAddress.parse('3FFE:FFFF:0:CD30::5678:1234'),
        PeerCastStation::Core::OutputStreamType.relay)
      assert_kind_of(PeerCastStation::Core::OutputListener, listener)
    end
    
    def test_get_end_point_no_listener_v4
      @peercast = PeerCastStation::Core::PeerCast.new
      @peercast.start_listen(
        System::Net::IPEndPoint.new(System::Net::IPAddress.IPv6Any, 7147),
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play |
        PeerCastStation::Core::OutputStreamType.interface,
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play |
        PeerCastStation::Core::OutputStreamType.interface)
      endpoint = @peercast.get_end_point(
        System::Net::IPAddress.parse('192.168.1.1'),
        PeerCastStation::Core::OutputStreamType.relay)
      assert_nil(endpoint)
    end
    
    def test_get_end_point_no_localrelay_listener_v4
      @peercast = PeerCastStation::Core::PeerCast.new
      @peercast.start_listen(
        System::Net::IPEndPoint.new(System::Net::IPAddress.any, 7147),
        PeerCastStation::Core::OutputStreamType.metadata,
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay)
      @peercast.start_listen(
        System::Net::IPEndPoint.new(System::Net::IPAddress.IPv6Any, 7147),
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play |
        PeerCastStation::Core::OutputStreamType.interface,
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play |
        PeerCastStation::Core::OutputStreamType.interface)
      endpoint = @peercast.get_end_point(
        System::Net::IPAddress.parse('192.168.1.1'),
        PeerCastStation::Core::OutputStreamType.relay)
      assert_nil(endpoint)
    end
    
    def test_get_end_point_localrelay_listener_v4
      @peercast = PeerCastStation::Core::PeerCast.new
      @peercast.start_listen(
        System::Net::IPEndPoint.new(System::Net::IPAddress.any, 7148),
        PeerCastStation::Core::OutputStreamType.none,
        PeerCastStation::Core::OutputStreamType.none)
      @peercast.start_listen(
        System::Net::IPEndPoint.new(System::Net::IPAddress.any, 7147),
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play |
        PeerCastStation::Core::OutputStreamType.interface,
        PeerCastStation::Core::OutputStreamType.none)
      endpoint = @peercast.get_end_point(
        System::Net::IPAddress.parse('192.168.1.1'),
        PeerCastStation::Core::OutputStreamType.relay)
      assert_equal(@peercast.local_address, endpoint.address)
      assert_equal(7147, endpoint.port)
    end
    
    def test_get_end_point_no_globalrelay_listener_v4
      @peercast = PeerCastStation::Core::PeerCast.new
      @peercast.global_address  = System::Net::IPAddress.parse('123.45.123.45')
      @peercast.global_address6 = System::Net::IPAddress.parse('3FFE:FFFF:0:CD30::5678:1234')
      @peercast.start_listen(
        System::Net::IPEndPoint.new(System::Net::IPAddress.any, 7147),
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay,
        PeerCastStation::Core::OutputStreamType.metadata)
      @peercast.start_listen(
        System::Net::IPEndPoint.new(System::Net::IPAddress.IPv6Any, 7147),
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play |
        PeerCastStation::Core::OutputStreamType.interface,
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play |
        PeerCastStation::Core::OutputStreamType.interface)
      endpoint = @peercast.get_end_point(
        System::Net::IPAddress.parse('123.45.67.8'),
        PeerCastStation::Core::OutputStreamType.relay)
      assert_nil(endpoint)
    end
    
    def test_get_end_point_globalrelay_listener_v4
      @peercast = PeerCastStation::Core::PeerCast.new
      @peercast.global_address  = System::Net::IPAddress.parse('123.45.123.45')
      @peercast.global_address6 = System::Net::IPAddress.parse('3FFE:FFFF:0:CD30::5678:1234')
      @peercast.start_listen(
        System::Net::IPEndPoint.new(System::Net::IPAddress.any, 7148),
        PeerCastStation::Core::OutputStreamType.none,
        PeerCastStation::Core::OutputStreamType.none)
      @peercast.start_listen(
        System::Net::IPEndPoint.new(System::Net::IPAddress.any, 7147),
        PeerCastStation::Core::OutputStreamType.none,
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play |
        PeerCastStation::Core::OutputStreamType.interface)
      endpoint = @peercast.get_end_point(
        System::Net::IPAddress.parse('123.45.67.8'),
        PeerCastStation::Core::OutputStreamType.relay)
      assert_equal(@peercast.global_address, endpoint.address)
      assert_equal(7147, endpoint.port)
    end
    
    def test_get_end_point_no_listener_v6
      @peercast = PeerCastStation::Core::PeerCast.new
      @peercast.start_listen(
        System::Net::IPEndPoint.new(System::Net::IPAddress.any, 7147),
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play |
        PeerCastStation::Core::OutputStreamType.interface,
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play |
        PeerCastStation::Core::OutputStreamType.interface)
      endpoint = @peercast.get_end_point(
        System::Net::IPAddress.parse('FEC0::1234:5678'),
        PeerCastStation::Core::OutputStreamType.relay)
      assert_nil(endpoint)
    end

    def test_get_end_point_no_localrelay_listener_v6
      @peercast = PeerCastStation::Core::PeerCast.new
      @peercast.start_listen(
        System::Net::IPEndPoint.new(System::Net::IPAddress.any, 7147),
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play |
        PeerCastStation::Core::OutputStreamType.interface,
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play |
        PeerCastStation::Core::OutputStreamType.interface)
      @peercast.start_listen(
        System::Net::IPEndPoint.new(System::Net::IPAddress.IPv6Any, 7147),
        PeerCastStation::Core::OutputStreamType.metadata,
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay)
      endpoint = @peercast.get_end_point(
        System::Net::IPAddress.parse('FEC0::1234:5678'),
        PeerCastStation::Core::OutputStreamType.relay)
      assert_nil(endpoint)
    end
    
    def test_get_end_point_localrelay_listener_v6
      @peercast = PeerCastStation::Core::PeerCast.new
      @peercast.start_listen(
        System::Net::IPEndPoint.new(System::Net::IPAddress.IPv6Any, 7148),
        PeerCastStation::Core::OutputStreamType.none,
        PeerCastStation::Core::OutputStreamType.none)
      @peercast.start_listen(
        System::Net::IPEndPoint.new(System::Net::IPAddress.IPv6Any, 7147),
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play |
        PeerCastStation::Core::OutputStreamType.interface,
        PeerCastStation::Core::OutputStreamType.none)
      endpoint = @peercast.get_end_point(
        System::Net::IPAddress.parse('FEC0::1234:5678'),
        PeerCastStation::Core::OutputStreamType.relay)
      assert_equal(@peercast.local_address6, endpoint.address)
      assert_equal(7147, endpoint.port)
    end
    
    def test_get_end_point_no_globalrelay_listener_v6
      @peercast = PeerCastStation::Core::PeerCast.new
      @peercast.global_address  = System::Net::IPAddress.parse('123.45.123.45')
      @peercast.global_address6 = System::Net::IPAddress.parse('3FFE:FFFF:0:CD30::5678:1234')
      @peercast.start_listen(
        System::Net::IPEndPoint.new(System::Net::IPAddress.any, 7147),
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play |
        PeerCastStation::Core::OutputStreamType.interface,
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play |
        PeerCastStation::Core::OutputStreamType.interface)
      @peercast.start_listen(
        System::Net::IPEndPoint.new(System::Net::IPAddress.IPv6Any, 7147),
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay,
        PeerCastStation::Core::OutputStreamType.metadata)
      endpoint = @peercast.get_end_point(
        System::Net::IPAddress.parse('3FFE:FFFF:0:CD30::1234:5678'),
        PeerCastStation::Core::OutputStreamType.relay)
      assert_nil(endpoint)
    end
    
    def test_get_end_point_globalrelay_listener_v6
      @peercast = PeerCastStation::Core::PeerCast.new
      @peercast.global_address  = System::Net::IPAddress.parse('123.45.123.45')
      @peercast.global_address6 = System::Net::IPAddress.parse('3FFE:FFFF:0:CD30::5678:1234')
      @peercast.start_listen(
        System::Net::IPEndPoint.new(System::Net::IPAddress.IPv6Any, 7148),
        PeerCastStation::Core::OutputStreamType.none,
        PeerCastStation::Core::OutputStreamType.none)
      @peercast.start_listen(
        System::Net::IPEndPoint.new(System::Net::IPAddress.IPv6Any, 7147),
        PeerCastStation::Core::OutputStreamType.none,
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play |
        PeerCastStation::Core::OutputStreamType.interface)
      endpoint = @peercast.get_end_point(
        System::Net::IPAddress.parse('3FFE:FFFF:0:CD30::1234:5678'),
        PeerCastStation::Core::OutputStreamType.relay)
      assert_equal(@peercast.global_address6, endpoint.address)
      assert_equal(7147, endpoint.port)
    end
    
    def test_relay_from_tracker
      @peercast = PeerCastStation::Core::PeerCast.new
      @peercast.source_stream_factories.add(MockSourceStreamFactory.new)
      
      tracker = System::Uri.new('pcp://127.0.0.1:7147')
      channel_id = System::Guid.empty
      assert_raise(System::ArgumentException) {
        @peercast.relay_channel(channel_id, tracker);
      }
      
      tracker = System::Uri.new('mock://127.0.0.1:7147')
      channel = @peercast.relay_channel(channel_id, tracker);
      assert_not_nil(channel)
      assert_kind_of(MockSourceStream, channel.source_stream)
      source = channel.source_stream
      assert_equal(tracker, source.tracker)
      assert_equal(channel, source.channel)
      assert_equal(1, source.log.size)
      assert_equal(:start, source.log[0][0])
      
      assert_equal(1, @peercast.channels.count)
      assert_equal(channel, @peercast.channels[0])
    end
    
    def test_relay_from_yp
      @peercast = PeerCastStation::Core::PeerCast.new
      @peercast.yellow_page_factories.add(MockYellowPageClientFactory.new)
      @peercast.source_stream_factories.add(MockSourceStreamFactory.new)
      @peercast.add_yellow_page('mock', 'mock_yp', System::Uri.new('pcp:example.com:7147'))
      
      channel_id = System::Guid.empty
      channel = @peercast.relay_channel(channel_id)
      assert_not_nil(channel)
      assert_kind_of(MockSourceStream, channel.source_stream)
      source = channel.source_stream
      sleep(0.1) until channel.is_closed
      assert_equal('127.0.0.1', source.tracker.host.to_s)
      assert_equal(7147,        source.tracker.port)
      assert_equal(channel,     source.channel)
      assert_equal(1, source.log.size)
      assert_equal(:start, source.log[0][0])
      
      assert_equal(1, @peercast.channels.count)
      assert_equal(channel, @peercast.channels[0])
    end

    def test_request_channel
      @peercast = PeerCastStation::Core::PeerCast.new
      @peercast.yellow_page_factories.add(MockYellowPageClientFactory.new)
      @peercast.source_stream_factories.add(MockSourceStreamFactory.new)
      @peercast.add_yellow_page('mock', 'mock_yp', System::Uri.new('pcp:example.com:7147'))
      
      channel_id = System::Guid.new_guid
      assert_nil(@peercast.request_channel(channel_id, nil, false))

      channel = PeerCastStation::Core::Channel.new(@peercast, channel_id, System::Uri.new('mock://localhost'))
      @peercast.add_channel(channel)
      assert_equal(channel, @peercast.request_channel(channel_id, nil, false))

      channel_id = System::Guid.new_guid
      channel = @peercast.request_channel(channel_id, System::Uri.new('mock://localhost'), true)
      assert_not_nil(channel)
      assert_kind_of(MockSourceStream, channel.source_stream)

      channel_id = System::Guid.new_guid
      channel = @peercast.request_channel(channel_id, nil, true)
      assert_not_nil(channel)
      assert_kind_of(MockSourceStream, channel.source_stream)
    end

    def test_broadcast_channel
      @peercast = PeerCastStation::Core::PeerCast.new
      yp = MockYellowPageClient.new(@peercast, System::Uri.new('pcp:example.com:7147'), 'pcp')
      @peercast.source_stream_factories.add(MockSourceStreamFactory.new)
      
      channel_id = System::Guid.new_guid
      source = System::Uri.new('mock://localhost/')
      reader = PCSCore::RawContentReaderFactory.new
      channel_info = PCSCore::AtomCollection.new
      channel_info.set_chan_info_name('foobar')
      channel_info = PCSCore::ChannelInfo.new(channel_info)
      channel = @peercast.broadcast_channel(yp, channel_id, channel_info, source, reader)

      assert_not_nil(channel)
      assert_kind_of(MockSourceStream, channel.source_stream)
      assert_kind_of(PCSCore::RawContentReader, channel.source_stream.reader)
    end

    def test_add_channel
      @peercast = PeerCastStation::Core::PeerCast.new
      channels = @peercast.channels
      assert_equal(0, channels.count)
      assert_equal(0, @peercast.channels.count)
      channel = PeerCastStation::Core::Channel.new(@peercast, System::Guid.new_guid, System::Uri.new('mock://localhost'))
      @peercast.add_channel(channel)
      assert_equal(0, channels.count)
      assert_equal(1, @peercast.channels.count)
      assert_equal(channel, @peercast.channels[0])
    end
    
    def test_close_channel
      tracker = System::Uri.new('mock://127.0.0.1:7147')
      @peercast = PeerCastStation::Core::PeerCast.new
      @peercast.source_stream_factories.add(MockSourceStreamFactory.new)
      channel_id = System::Guid.empty
      channel = @peercast.relay_channel(channel_id, tracker);
      assert_equal(1, @peercast.channels.count)
      @peercast.close_channel(channel)
      assert_equal(0, @peercast.channels.count)
    end
    
    def test_output_connection
      @peercast = PeerCastStation::Core::PeerCast.new
      @peercast.start_listen(
        System::Net::IPEndPoint.new(System::Net::IPAddress.any, 7147),
        PeerCastStation::Core::OutputStreamType.interface |
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play,
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay)
      local_end_point  = @peercast.get_local_end_point(System::Net::Sockets::AddressFamily.inter_network, PeerCastStation::Core::OutputStreamType.relay)
      global_end_point = @peercast.get_global_end_point(System::Net::Sockets::AddressFamily.inter_network, PeerCastStation::Core::OutputStreamType.relay)
      assert_not_nil(local_end_point)
      assert_equal(@peercast.local_address, local_end_point.address)
      assert_equal(7147, local_end_point.port)
      assert_nil(global_end_point)
      @peercast.global_address = @peercast.local_address
      global_end_point = @peercast.get_global_end_point(System::Net::Sockets::AddressFamily.inter_network, PeerCastStation::Core::OutputStreamType.relay)
      assert_not_nil(global_end_point)
      
      output_stream_factory = MockOutputStreamFactory.new(
        PeerCastStation::Core::OutputStreamType.metadata)
      @peercast.output_stream_factories.add(output_stream_factory)
      
      sock = TCPSocket.new('localhost', 7147)
      sock.write('mock 9778E62BDC59DF56F9216D0387F80BF2')
      sock.close
      
      sleep(1)
      assert_equal(2, output_stream_factory.log.size)
      assert_equal(:parse_channel_id, output_stream_factory.log[0][0])
      assert_equal(:create,           output_stream_factory.log[1][0])
    end
    
    def test_output_connection_not_acceptable
      #ループバックアドレスからの接続は常に許可するので
      #テストできないため保留
    end
    
    def test_listen
      @peercast = PeerCastStation::Core::PeerCast.new
      listener = @peercast.StartListen(
        System::Net::IPEndPoint.new(System::Net::IPAddress.any, 7147),
        PeerCastStation::Core::OutputStreamType.interface |
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play,
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay)
      assert(!listener.is_closed)
      assert_equal(System::Net::IPAddress.any, listener.local_end_point.address)
      assert_equal(7147,                       listener.local_end_point.port)
      assert_equal(
        PeerCastStation::Core::OutputStreamType.interface |
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay |
        PeerCastStation::Core::OutputStreamType.play,
        listener.local_output_accepts)
      assert_equal(
        PeerCastStation::Core::OutputStreamType.metadata |
        PeerCastStation::Core::OutputStreamType.relay,
        listener.global_output_accepts)
      assert_not_nil(@peercast.get_local_end_point(System::Net::Sockets::AddressFamily.inter_network, PeerCastStation::Core::OutputStreamType.relay))
      @peercast.StopListen(listener)
      assert(listener.is_closed)
      assert_nil(@peercast.get_local_end_point(System::Net::Sockets::AddressFamily.inter_network, PeerCastStation::Core::OutputStreamType.relay))
    end

    context 'is_firewalled' do
      setup do
        @peercast = PeerCastStation::Core::PeerCast.new
      end

      teardown do
        @peercast.stop
      end

      should '起動時はnil' do
        assert_nil @peercast.is_firewalled
      end

      context 'trueのとき' do
        should 'start_listenでWANのリレー待ち受けを開始するとnilになる' do
          @peercast.is_firewalled = true
          listener = @peercast.start_listen(
            System::Net::IPEndPoint.new(System::Net::IPAddress.any, 7147),
            PeerCastStation::Core::OutputStreamType.all,
            PeerCastStation::Core::OutputStreamType.relay)
          assert_nil @peercast.is_firewalled
        end

        should 'stop_listenでWANのリレー待ち受けを停止してもかわらない' do
          listener = @peercast.start_listen(
            System::Net::IPEndPoint.new(System::Net::IPAddress.any, 7147),
            PeerCastStation::Core::OutputStreamType.all,
            PeerCastStation::Core::OutputStreamType.relay)
          @peercast.is_firewalled = true
          @peercast.stop_listen(listener)
          assert_equal true, @peercast.is_firewalled
        end

        should '既に待ち受けているリスナーのWANのリレー待ち受けを許可するとnilになる' do
          listener = @peercast.start_listen(
            System::Net::IPEndPoint.new(System::Net::IPAddress.any, 7147),
            PeerCastStation::Core::OutputStreamType.all,
            PeerCastStation::Core::OutputStreamType.none)
          @peercast.is_firewalled = true
          listener.global_output_accepts = PeerCastStation::Core::OutputStreamType.relay
          assert_nil @peercast.is_firewalled
        end

        should '既に待ち受けているリスナーのWANのリレー待ち受けを不許可にしてもかわらない' do
          listener = @peercast.start_listen(
            System::Net::IPEndPoint.new(System::Net::IPAddress.any, 7147),
            PeerCastStation::Core::OutputStreamType.all,
            PeerCastStation::Core::OutputStreamType.all)
          @peercast.is_firewalled = true
          listener.global_output_accepts = PeerCastStation::Core::OutputStreamType.none
          assert_equal true, @peercast.is_firewalled
        end
      end

      context 'falseのとき' do
        should 'start_listenでWANのリレー待ち受けを開始してもかわらない' do
          @peercast.is_firewalled = false
          listener = @peercast.start_listen(
            System::Net::IPEndPoint.new(System::Net::IPAddress.any, 7147),
            PeerCastStation::Core::OutputStreamType.all,
            PeerCastStation::Core::OutputStreamType.relay)
          assert_equal false, @peercast.is_firewalled
        end

        should 'stop_listenでWANのリレー待ち受けを停止するとnilになる' do
          listener = @peercast.start_listen(
            System::Net::IPEndPoint.new(System::Net::IPAddress.any, 7147),
            PeerCastStation::Core::OutputStreamType.all,
            PeerCastStation::Core::OutputStreamType.relay)
          @peercast.is_firewalled = false
          @peercast.stop_listen(listener)
          assert_nil @peercast.is_firewalled
        end

        should '既に待ち受けているリスナーのWANのリレー待ち受けを許可してもかわらない' do
          listener = @peercast.start_listen(
            System::Net::IPEndPoint.new(System::Net::IPAddress.any, 7147),
            PeerCastStation::Core::OutputStreamType.all,
            PeerCastStation::Core::OutputStreamType.none)
          @peercast.is_firewalled = false
          listener.global_output_accepts = PeerCastStation::Core::OutputStreamType.relay
          assert_equal false, @peercast.is_firewalled
        end

        should '既に待ち受けているリスナーのWANのリレー待ち受けを不許可にするとnilになる' do
          listener = @peercast.start_listen(
            System::Net::IPEndPoint.new(System::Net::IPAddress.any, 7147),
            PeerCastStation::Core::OutputStreamType.all,
            PeerCastStation::Core::OutputStreamType.all)
          @peercast.is_firewalled = false
          listener.global_output_accepts = PeerCastStation::Core::OutputStreamType.none
          assert_nil @peercast.is_firewalled
        end
      end
    end
  end
end

