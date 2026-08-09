using MusicaAprender.EmailDeliveryVerifier;

var options =
    EmailDeliveryVerificationOptions.Load(args);

await EmailDeliveryChecks.RunAsync(options);
