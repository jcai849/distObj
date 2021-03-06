worker <- function(comms, log, host, port) {

	library("largeScaleR")

	commsProcess(largeScaleR::host(comms), largeScaleR::port(comms),
		     user(comms), pass(comms), dbpass(comms), FALSE)
	logProcess(largeScaleR::host(log), largeScaleR::port(log), FALSE)
	userProcess(host, if (missing(port)) largeScaleR::port() else port)
	init()

	repeat {
		keys <- queue(c(ls(.largeScaleRChunks), ls(.largeScaleRKeys)))
		request <- read(keys)
		result <- tryCatch(evaluate(fun(request), args(request),
					    target(request),
					    largeScaleR::desc(request)), 
				   error =  identity)
		addChunk(largeScaleR::desc(request), result)
		respond(largeScaleR::desc(request), result)
	}
}

queue <- function(x) {class(x) <- "queue"; x}

read.queue <- function(x) {
	log(paste("reading queues: ", paste(x, collapse="\n"), sep="\n"))
	while (is.null(serializedMsg <- 
		rediscc::redis.pop(getCommsConn(), x, timeout=10))) {}
	unserialize(charToRaw(serializedMsg))
}

evaluate <- function(fun, args, target, cd) {
	stopifnot(is.list(args))
	args <- lapply(args, unstub, target=target)
	log(paste("evaluating", paste(format(fun), collapse="\n")))
	do.call(fun, args, envir=.GlobalEnv)
}

respond <- function(cd, chunk) {
	post(cd, chunk)
	interest <- checkInterest(cd)
	respondInterest(cd, interest)
}

post <- function(cd, chunk) {
	selfProcess <- get("userProcess", envir = .largeScaleRProcesses)
	keys <- list(avail	= TRUE,
		     preview 	= tryCatch(preview(chunk), error=function(e)
						"no preview"),
		     size 	= size(chunk),
		     host	= host(selfProcess),
		     port	= port(selfProcess))
	log(paste("posting information on chunk", format(cd)))
	rediscc::redis.set(getCommsConn(), paste0(cd, names(keys)), keys)
}

checkInterest <- function(cd) {
	log(paste("checking interest for", format(cd)))
	interest <- rediscc::redis.get(getCommsConn(), paste0(cd, "interest"))
	if (is.null(interest)) 0L else as.integer(interest)
}

respondInterest <- function(cd, interest) {
	log(paste("responding to interest for", format(cd)))
	if (interest == 0L) return()
	for (i in seq(interest))
		send(complete = TRUE, loc=paste0(cd, "response"))
	return()
}
