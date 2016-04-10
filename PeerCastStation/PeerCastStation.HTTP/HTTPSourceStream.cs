﻿using System;
using System.Collections.Generic;
using System.Linq;
using PeerCastStation.Core;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace PeerCastStation.HTTP
{
  /// <summary>
  ///サーバからのHTTPレスポンス内容を保持するクラスです
  /// </summary>
  public class HTTPResponse
  {
    /// <summary>
    /// HTTPバージョンを取得および設定します
    /// </summary>
    public string Version { get; private set; }
    /// <summary>
    /// HTTPステータスを取得および設定します
    /// </summary>
    public int Status { get; private set; }
    /// <summary>
    /// レスポンスヘッダの値のコレクション取得します
    /// </summary>
    public Dictionary<string, string> Headers { get; private set; }

    /// <summary>
    /// HTTPレンスポンス文字列からHTTPResponseオブジェクトを構築します
    /// </summary>
    /// <param name="response">行毎に区切られたHTTPレスポンスの文字列表現</param>
    public HTTPResponse(IEnumerable<string> requests)
    {
      Headers = new Dictionary<string, string>();
      foreach (var req in requests) {
        Match match = null;
        if ((match = Regex.Match(req, @"^HTTP/(1.\d) (\d+) .*$")).Success) {
          this.Version = match.Groups[1].Value;
          this.Status = Int32.Parse(match.Groups[2].Value);
        }
        else if ((match = Regex.Match(req, @"^(\S*):\s*(.*)\s*$", RegexOptions.IgnoreCase)).Success) {
          Headers[match.Groups[1].Value.ToUpperInvariant()] = match.Groups[2].Value;
        }
      }
    }
  }

  /// <summary>
  /// ストリームからHTTPレスポンスを読み取るクラスです
  /// </summary>
  public static class HTTPResponseReader
  {
    public static async Task<HTTPResponse> ReadAsync(Stream stream, CancellationToken cancel_token)
    {
      string line = null;
      var requests = new List<string>();
      var buf = new List<byte>();
      var length = 0;
      while (line!="") {
        var value = await stream.ReadByteAsync(cancel_token);
        if (value<0) {
          throw new EndOfStreamException();
        }
        buf.Add((byte)value);
        length += 1;
        if (buf.Count>=2 && buf[buf.Count-2]=='\r' && buf[buf.Count-1]=='\n') {
          line = System.Text.Encoding.UTF8.GetString(buf.ToArray(), 0, buf.Count - 2);
          if (line!="") requests.Add(line);
          buf.Clear();
        }
        else if (length>4096) {
          throw new InvalidDataException();
        }
      }
      return new HTTPResponse(requests);
    }
  }

  public class HTTPSourceStreamFactory
    : SourceStreamFactoryBase
  {
    public override string Name { get { return "http"; } }
    public override string Scheme { get { return "http"; } }
    public override SourceStreamType Type {
      get { return SourceStreamType.Broadcast; }
    }
    public override Uri DefaultUri {
      get { return new Uri("http://localhost:8080/"); }
    }
    public override bool IsContentReaderRequired {
      get { return true; }
    }

    public override ISourceStream Create(Channel channel, Uri source, IContentReader reader)
    {
      return new HTTPSourceStream(this.PeerCast, channel, source, reader);
    }

    public HTTPSourceStreamFactory(PeerCast peercast)
      : base(peercast)
    {
    }
  }

  public class HTTPSourceConnection
    : SourceConnectionBase
  {
    private IContentReader contentReader;
    private HTTPResponse response = null;
    private bool useContentBitrate;
    private long lastPosition = 0;

    public HTTPSourceConnection(
        PeerCast peercast,
        Channel  channel,
        Uri      source_uri,
        IContentReader content_reader,
        bool use_content_bitrate)
      : base(peercast, channel, source_uri)
    {
      contentReader = content_reader;
      useContentBitrate = use_content_bitrate;
    }

    protected override async Task<SourceConnectionClient> DoConnect(Uri source, CancellationToken cancel_token)
    {
      try {
        var client = new TcpClient();
        if (source.HostNameType==UriHostNameType.IPv4 ||
            source.HostNameType==UriHostNameType.IPv6) {
          await client.ConnectAsync(IPAddress.Parse(source.Host), source.Port);
        }
        else {
          await client.ConnectAsync(source.DnsSafeHost, source.Port);
        }
        var connection = new SourceConnectionClient(client);
        connection.Stream.ReadTimeout  = 10000;
        connection.Stream.WriteTimeout = 8000;
        return connection;
      }
      catch (SocketException e) {
        Logger.Error(e);
        return null;
      }
    }

    protected override async Task DoProcess(CancellationToken cancel_token)
    {
      try {
        this.Status = ConnectionStatus.Connecting;
        var host = SourceUri.DnsSafeHost;
        if (SourceUri.Port!=-1 && SourceUri.Port!=80) {
          host = String.Format("{0}:{1}", SourceUri.DnsSafeHost, SourceUri.Port);
        }
        var request = String.Format(
            "GET {0} HTTP/1.1\r\n" +
            "Host: {1}\r\n" +
            "User-Agent: NSPlayer ({2})\r\n" +
            "Connection: close\r\n" +
            "Pragma: stream-switch\r\n" +
            "\r\n",
            SourceUri.PathAndQuery,
            host,
            PeerCast.AgentName);
        await connection.Stream.WriteAsync(System.Text.Encoding.UTF8.GetBytes(request));
        Logger.Debug("Sending request:\n" + request);

        response = null;
        response = await HTTPResponseReader.ReadAsync(connection.Stream, cancel_token);
        if (response.Status!=200) {
          Logger.Error("Server responses {0} to GET {1}", response.Status, SourceUri.PathAndQuery);
          Stop(response.Status==404 ? StopReason.OffAir : StopReason.UnavailableError);
        }

        this.Status = ConnectionStatus.Connected;
        while (!IsStopped) {
          var data = await contentReader.ReadAsync(connection.Stream, cancel_token);
          if (data.ChannelInfo!=null) {
            Channel.ChannelInfo = UpdateChannelInfo(Channel.ChannelInfo, data.ChannelInfo);
          }
          if (data.ChannelTrack!=null) {
            Channel.ChannelTrack = UpdateChannelTrack(Channel.ChannelTrack, data.ChannelTrack);
          }
          if (data.ContentHeader!=null) {
            Channel.ContentHeader = data.ContentHeader;
            Channel.Contents.Clear();
            lastPosition = data.ContentHeader.Position;
          }
          if (data.Contents!=null) {
            foreach (var content in data.Contents) {
              Channel.Contents.Add(content);
              lastPosition = content.Position;
            }
          }
        }
      }
      catch (InvalidDataException) {
        Stop(StopReason.ConnectionError);
      }
      catch (OperationCanceledException) {
        Logger.Error("Recv content timed out");
        Stop(StopReason.ConnectionError);
      }
      catch (IOException) {
        Stop(StopReason.ConnectionError);
      }
      this.Status = ConnectionStatus.Error;
    }

    private ChannelInfo UpdateChannelInfo(ChannelInfo a, ChannelInfo b)
    {
      var base_atoms = new AtomCollection(a.Extra);
      var new_atoms  = new AtomCollection(b.Extra);
      if (!useContentBitrate) {
        new_atoms.RemoveByName(Atom.PCP_CHAN_INFO_BITRATE);
      }
      base_atoms.Update(new_atoms);
      return new ChannelInfo(base_atoms);
    }

    private ChannelTrack UpdateChannelTrack(ChannelTrack a, ChannelTrack b)
    {
      var base_atoms = new AtomCollection(a.Extra);
      base_atoms.Update(b.Extra);
      return new ChannelTrack(base_atoms);
    }

    public override ConnectionInfo GetConnectionInfo()
    {
      IPEndPoint endpoint = connection!=null ? connection.RemoteEndPoint : null;
      string server_name = "";
      if (response==null || !response.Headers.TryGetValue("SERVER", out server_name)) {
        server_name = "";
      }
      return new ConnectionInfo(
        "HTTP Source",
        ConnectionType.Source,
        Status,
        SourceUri.ToString(),
        endpoint,
        (endpoint!=null && endpoint.Address.IsSiteLocal()) ? RemoteHostStatus.Local : RemoteHostStatus.None,
        lastPosition,
        RecvRate,
        SendRate,
        null,
        null,
        server_name);
    }

  }

  public class HTTPSourceStream
    : SourceStreamBase
  {
    public IContentReader ContentReader { get; private set; }
    public bool UseContentBitrate { get; private set; }

    public HTTPSourceStream(PeerCast peercast, Channel channel, Uri source_uri, IContentReader reader)
      : base(peercast, channel, source_uri)
    {
      this.ContentReader = reader;
      this.UseContentBitrate = channel.ChannelInfo==null || channel.ChannelInfo.Bitrate==0;
    }

    public override ConnectionInfo GetConnectionInfo()
    {
      if (sourceConnection!=null) {
        return sourceConnection.GetConnectionInfo();
      }
      else {
        ConnectionStatus status;
        switch (StoppedReason) {
        case StopReason.UserReconnect: status = ConnectionStatus.Connecting; break;
        case StopReason.UserShutdown:  status = ConnectionStatus.Idle; break;
        default:                       status = ConnectionStatus.Error; break;
        }
        IPEndPoint endpoint = null;
        string server_name = "";
        return new ConnectionInfo(
          "HTTP Source",
          ConnectionType.Source,
          status,
          SourceUri.ToString(),
          endpoint,
          RemoteHostStatus.None,
          null,
          null,
          null,
          null,
          null,
          server_name);
      }
    }

    protected override ISourceConnection CreateConnection(Uri source_uri)
    {
      return new HTTPSourceConnection(PeerCast, Channel, source_uri, ContentReader, UseContentBitrate);
    }

    protected override void OnConnectionStopped(ISourceConnection connection, StopReason reason)
    {
      switch (reason) {
      case StopReason.UserReconnect:
        break;
      case StopReason.UserShutdown:
        Stop(reason);
        break;
      default:
        Task.Delay(3000).ContinueWith(prev => Reconnect());
        break;
      }
    }

    public override SourceStreamType Type
    {
      get { return SourceStreamType.Broadcast; }
    }
  }

  [Plugin]
  class HTTPSourceStreamPlugin
    : PluginBase
  {
    override public string Name { get { return "HTTP Source"; } }

    private HTTPSourceStreamFactory factory;
    override protected void OnAttach()
    {
      if (factory==null) factory = new HTTPSourceStreamFactory(Application.PeerCast);
      Application.PeerCast.SourceStreamFactories.Add(factory);
    }

    override protected void OnDetach()
    {
      Application.PeerCast.SourceStreamFactories.Remove(factory);
    }
  }
}
