using Microsoft.AspNetCore.Mvc;

namespace Microservice.Controllers
{
    [ApiController]
    [Route("api/hello")]
    public class HelloController : ControllerBase
    {
        [HttpGet]
        public IActionResult GetMessage()
        {
            return Ok("Hello from Alok!!!!!!!!");
        }
    }
}
