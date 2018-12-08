using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.Internal;
using Microsoft.Extensions.Logging;
using System;
using System.IO;
using System.Threading.Tasks;

namespace TodoWebApp.Logging
{
    /// <summary>
    /// Logs HTTP requests and responses.
    /// </summary>
    public class LoggingMiddleware
    {
        private const int RESPONSE_BUFFER_SIZE_IN_BYTES = 1024 * 1024;
    
        private readonly RequestDelegate nextRequestDelegate;
        private readonly IHttpContextLoggingHandler httpContextLoggingHandler;
        private readonly IHttpLogMessageConverter httpLogMessageConverter;
        private readonly ILogger logger;

        /// <summary>
        /// Creates a new instance of the <see cref="LoggingMiddleware"/> class.
        /// </summary>
        /// <param name="nextRequestDelegate"></param>
        /// <param name="httpContextLoggingHandler"></param>
        /// <param name="httpLogMessageConverter"></param>
        /// <param name="logger"></param>
        public LoggingMiddleware(RequestDelegate nextRequestDelegate
                               , IHttpContextLoggingHandler httpContextLoggingHandler
                               , IHttpLogMessageConverter httpLogMessageConverter
                               , ILogger<LoggingMiddleware> logger)
        {
            this.nextRequestDelegate = nextRequestDelegate ?? throw new ArgumentNullException(nameof(nextRequestDelegate));
            this.httpContextLoggingHandler = httpContextLoggingHandler ?? throw new ArgumentNullException(nameof(httpContextLoggingHandler));
            this.httpLogMessageConverter = httpLogMessageConverter ?? throw new ArgumentNullException(nameof(httpLogMessageConverter));
            this.logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        /// <summary>
        /// Processes the given <paramref name="httpContext"/> object.
        /// </summary>
        /// <param name="httpContext">The current HTTP context to be processed.</param>
        /// <returns></returns>
        public async Task Invoke(HttpContext httpContext)
        {
            if (httpContextLoggingHandler.ShouldLog(httpContext))
            {
                await Log(httpContext);
            }
            else
            {
                await nextRequestDelegate(httpContext);
            }
        }

        /// <summary>
        /// Logs the <see cref="HttpContext.Request"/> and <see cref="HttpContext.Response"/> properties of the given <paramref name="httpContext"/> object.
        /// </summary>
        /// <param name="httpContext">The <see cref="HttpContext"/> object to be logged.</param>
        /// <returns></returns>
        private async Task Log(HttpContext httpContext)
        {
            // Ensure the current HTTP request is seekable and thus can be read and reset many times, including for logging purposes
            httpContext.Request.EnableRewind();

            // Logs the current HTTP request
            var httpRequestAsLogMessage = httpLogMessageConverter.ToLogMessage(httpContext.Request);
            logger.LogDebug(httpRequestAsLogMessage);

            // Replace response body stream with a seekable one, like a MemoryStream, to allow logging it
            var originalResponseBodyStream = httpContext.Response.Body;

            using (var stream = new MemoryStream(RESPONSE_BUFFER_SIZE_IN_BYTES))
            {
                httpContext.Response.Body = stream;
                await nextRequestDelegate(httpContext);

                // Logs the current HTTP response
                var httpResponseAsLogMessage = httpLogMessageConverter.ToLogMessage(httpContext.Response);
                logger.LogDebug(httpResponseAsLogMessage);

                // Ensure the original HTTP response is sent to the next middleware
                await stream.CopyToAsync(originalResponseBodyStream);
            }
        }
    }
}