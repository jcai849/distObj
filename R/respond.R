queue <- function(x) {class(x) <- "queue"; x}

read.queue <- function(x) {
	info("Awaiting message on queues:", format(x))
	while (is.null(serializedMsg <- rediscc::redis.pop(commsConn(), x,
							   timeout=10))) {}
	m <- unserialize(charToRaw(serializedMsg))
	info("Received message")
	m
}

evaluate <- function(fun, args, target, cd) {
	stopifnot(is.list(args))
	args <- lapply(args, unstub, target=target)
	info("Performing requested function")
	chunk <- do.call(fun, args, envir=.GlobalEnv)
}

respond <- function(cd, chunk) {
	post(cd, chunk)
	interest <- checkInterest(cd)
	respondInterest(cd, interest)
}

post <- function(cd, chunk) {
	selfProcess <- get("userProcess", envir = .largeScaleRProcesses)
	keys <- list(avail	= TRUE,
		     preview 	= preview(chunk),
		     size 	= size(chunk),
		     host	= host(selfProcess),
		     port	= port(selfProcess))
	rediscc::redis.set(commsConn(), paste0(cd, names(keys)), keys)
}

checkInterest <- function(cd) {
	interest <- rediscc::redis.get(commsConn(), paste0(cd, "interest"))
	if (is.null(interest)) 0L else as.integer(interest)
}

respondInterest <- function(cd, interest) {
	if (interest == 0L) return()
	for (i in seq(interest))
		send(complete = TRUE, loc=paste0(cd, "response"))
	return()
}