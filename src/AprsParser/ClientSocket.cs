using System;
using System.Diagnostics;
using System.Net.Sockets;

namespace aprsparser
{
    public class ClientSocket
    {
        #region Delegate Method Types

        /// <summary> Called when a message is received </summary>
        public delegate void MessageHandler(ClientSocket socket, int size);

        /// <summary> Called when a connection is closed </summary>
        public delegate void CloseHandler(ClientSocket socket);

        /// <summary> Called when a socket error occurs </summary>
        public delegate void ErrorHandler(ClientSocket socket, Exception ex);

        #endregion

        #region Exception classes

        public class SocketClosedException : SocketException { };

        #endregion

        #region Private Properties

        private TcpClient _tcpClient;
        private NetworkStream _networkStream;
        private readonly AsyncCallback _callbackReadMethod;
        private readonly AsyncCallback _callbackWriteMethod;
        private readonly MessageHandler _messageHandler;
        private readonly CloseHandler _closeHandler;
        private readonly ErrorHandler _errorHandler;
        private bool _isDisposed;

        #endregion

        #region Public Properties

        /// <summary> The IpAddress the client is connect to </summary>
        public string IpAddress { get; set; }

        /// <summary> The Port to either connect to or listen on </summary>
        public int Port { get; set; }

        /// <summary> A reference to a user defined object </summary>
        public object UserData { get; set; }

        /// <summary> A raw buffer to capture data coming off the socket </summary>
        public byte[] Buffer { get; set; }

        /// <summary> Size of the raw buffer for received socket data </summary>
        public int BufferSize { get; set; }

        public Socket Socket => _tcpClient.Client;

        #endregion

        #region Constructor, Finalize, Dispose

        /// <summary> Constructor for client support </summary>
        /// <param name="bufferSize"> The size of the raw buffer </param>
        /// <param name="userData"> A Reference to the Users arguments </param>
        /// <param name="messageHandler"> Reference to the user defined message handler method </param>
        /// <param name="closeHandler"> Reference to the user defined close handler method </param>
        /// <param name="errorHandler"> Reference to the user defined error handler method </param>
        public ClientSocket(Int32 bufferSize, Object userData, MessageHandler messageHandler, CloseHandler
            closeHandler, ErrorHandler errorHandler)
        {
            //create the raw buffer
            BufferSize = bufferSize;
            Buffer = new Byte[BufferSize];

            //save the user argument
            UserData = userData;

            //set the handler methods
            _messageHandler = messageHandler;
            _closeHandler = closeHandler;
            _errorHandler = errorHandler;

            //set the async socket method handlers
            _callbackReadMethod = ReceiveComplete;
            _callbackWriteMethod = SendComplete;

            //init the dispose flag
            _isDisposed = false;
        }

        //**************************************************
        /// <summary> Finalize </summary>
        ~ClientSocket()
        {
            if (!_isDisposed)
                Dispose();
        }

        //***********************************************
        /// <summary> Dispose </summary>
        public void Dispose()
        {
            try
            {
                //flag that dispose has been called
                _isDisposed = true;

                //disconnect the client from the server
                Disconnect();
            }
            catch (Exception ex)
            {
                Debug.WriteLine(ex.ToString());
                if (_errorHandler != null)
                    _errorHandler(this, ex);
            }
        }

        #endregion

        #region Private Methods

        //*********************************************
        /// <summary> Called when a message arrives </summary>
        /// <param name="ar"> RefType: An async result interface </param>
        private void ReceiveComplete(IAsyncResult ar)
        {
            try
            {
                // Is the Network Stream object valid
                if (_networkStream.CanRead)
                {
                    // Read the current bytes from the stream buffer
                    int iBytesRecieved = _networkStream.EndRead(ar);
                    // If there are bytes to process else the connection is lost
                    if (iBytesRecieved > 0)
                    {
                        try
                        {
                            //a message came in send it to the MessageHandler
                            _messageHandler(this, iBytesRecieved);
                        }
                        catch (Exception ex)
                        {
                            Debug.WriteLine(ex.ToString());
                            if (_errorHandler != null)
                                _errorHandler(this, ex);
                        }
                    }
                    //wait for a new message
                    Receive();
                }
            }
            catch (Exception)
            {
                try
                {
                    //the connection must have dropped call the CloseHandler
                    _closeHandler(this);
                }
                catch (Exception ex)
                {
                    Debug.WriteLine(ex.ToString());
                    if (_errorHandler != null)
                        _errorHandler(this, ex);
                }
                //dispose of the class
                Dispose();
            }
        }

        //*********************************************
        /// <summary> Called when a message is sent </summary>
        /// <param name="ar"> RefType: An async result interface </param>
        private void SendComplete(IAsyncResult ar)
        {
            try
            {
                // Is the Network Stream object valid
                if (_networkStream.CanWrite)
                    _networkStream.EndWrite(ar);
            }
            catch (Exception ex)
            {
                Debug.WriteLine(ex.ToString());
                if (_errorHandler != null)
                    _errorHandler(this, ex);
            }
        }

        #endregion

        #region Public Methods

        //********************************************
        /// <summary> Function used to connect to a server </summary>
        /// <param name="address"> The address to connect to </param>
        /// <param name="port"> The Port to connect to </param>
        public void Connect(string address, int port)
        {
            try
            {
                if (_networkStream == null)
                {
                    // Set the Ipaddress and Port
                    IpAddress = address;
                    Port = port;
                    // Attempt to establish a connection
                    _tcpClient = new TcpClient(IpAddress, Port);
                    _networkStream = _tcpClient.GetStream();
                    // Set these socket options
                    _tcpClient.ReceiveBufferSize = 1048576;
                    _tcpClient.SendBufferSize = 1048576;
                    _tcpClient.NoDelay = true;
                    _tcpClient.LingerState = new LingerOption(false, 0);
                    // Start to receive messages
                    Receive();
                }
            }
            catch (SocketException e)
            {
                throw new Exception(e.Message, e.InnerException);
            }
        }

        //***********************************************
        /// <summary> Function used to disconnect from the server </summary>
        public void Disconnect()
        {
            //close down the connection
            if (_networkStream != null)
                _networkStream.Close();
            if (_tcpClient != null)
                _tcpClient.Close();

            //clean up the connection state
            _networkStream = null;
            _tcpClient = null;
        }

        //***************************************************
        /// <summary> Function to send a string to the server </summary>
        /// <param name="message"> A string to send </param>
        public void Send(string message)
        {
            if ((_networkStream != null) && (_networkStream.CanWrite))
            {
                // Convert the string into a Raw Buffer
                Byte[] pRawBuffer = System.Text.Encoding.ASCII.GetBytes(message);
                // Issue an asynchronous write
                _networkStream.BeginWrite(pRawBuffer, 0, pRawBuffer.GetLength(0), _callbackWriteMethod, null);
            }
            else
                throw new SocketClosedException();
        }
        //************************************************
        /// <summary> Function to send a raw buffer to the server </summary>
        /// <param name="pRawBuffer"> A Raw buffer of bytes to send </param>
        public void Send(Byte[] pRawBuffer)
        {
            if ((_networkStream != null) && (_networkStream.CanWrite))
            {
                // Issue an asynchronous write
                _networkStream.BeginWrite(pRawBuffer, 0, pRawBuffer.GetLength(0), _callbackWriteMethod, null);
            }
            else
                throw new SocketClosedException();
        }

        //**********************************************
        /// <summary> Wait for a message to arrive </summary>
        public void Receive()
        {
            if ((_networkStream != null) && (_networkStream.CanRead))
            {
                // Issue an asynchronous read
                _networkStream.BeginRead(Buffer, 0, BufferSize, _callbackReadMethod, null);
            }
            else
                throw new SocketClosedException();
        }

        #endregion
    }
}