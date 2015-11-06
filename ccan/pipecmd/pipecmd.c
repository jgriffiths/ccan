/* CC0 license (public domain) - see LICENSE file for details */
#include <ccan/pipecmd/pipecmd.h>
#include <ccan/noerr/noerr.h>
#include <stdlib.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>

static char **gather_args(const char *arg0, va_list ap)
{
	size_t n = 1;
	char **arr = calloc(sizeof(char *), n + 1);

	if (!arr)
		return NULL;
	arr[0] = (char *)arg0;

	while ((arr[n++] = va_arg(ap, char *)) != NULL) {
		arr = realloc(arr, sizeof(char *) * (n + 1));
		if (!arr)
			return NULL;
	}
	return arr;
}

pid_t pipecmdv(int *fd_fromchild, int *fd_tochild, const char *cmd, va_list ap)
{
	int tochild[2], fromchild[2], execfail[2];
	pid_t childpid;
	int err;

	if (fd_tochild) {
		if (pipe(tochild) != 0)
			goto fail;
	} else {
		tochild[0] = open("/dev/null", O_RDONLY);
		if (tochild[0] < 0)
			goto fail;
	}
	if (fd_fromchild) {
		if (pipe(fromchild) != 0)
			goto close_tochild_fail;
	} else {
		fromchild[1] = open("/dev/null", O_WRONLY);
		if (fromchild[1] < 0)
			goto close_tochild_fail;
	}
	if (pipe(execfail) != 0)
		goto close_fromchild_fail;

	if (fcntl(execfail[1], F_SETFD, fcntl(execfail[1], F_GETFD)
		  | FD_CLOEXEC) < 0)
		goto close_execfail_fail;

	childpid = fork();
	if (childpid < 0)
		goto close_execfail_fail;

	if (childpid == 0) {
		char **args = gather_args(cmd, ap);

		if (fd_tochild)
			close(tochild[1]);
		if (fd_fromchild)
			close(fromchild[0]);
		close(execfail[0]);

		// Child runs command.
		if (!args)
			err = ENOMEM;
		else {
			if (tochild[0] != STDIN_FILENO) {
				if (dup2(tochild[0], STDIN_FILENO) == -1)
					goto child_errno_fail;
				close(tochild[0]);
			}
			if (fromchild[1] != STDOUT_FILENO) {
				if (dup2(fromchild[1], STDOUT_FILENO) == -1)
					goto child_errno_fail;
				close(fromchild[1]);
			}
			execvp(cmd, args);
		child_errno_fail:
			err = errno;
		}
		write(execfail[1], &err, sizeof(err));
		exit(127);
	}

	close(tochild[0]);
	close(fromchild[1]);
	close(execfail[1]);
	/* Child will close this without writing on successful exec. */
	if (read(execfail[0], &err, sizeof(err)) == sizeof(err)) {
		waitpid(childpid, NULL, 0);
		errno = err;
		return -1;
	}
	if (fd_tochild)
		*fd_tochild = tochild[1];
	if (fd_fromchild)
		*fd_fromchild = fromchild[0];
	return childpid;

close_execfail_fail:
	close_noerr(execfail[0]);
	close_noerr(execfail[1]);
close_fromchild_fail:
	if (fd_fromchild)
		close_noerr(fromchild[0]);
	close_noerr(fromchild[1]);
close_tochild_fail:
	close_noerr(tochild[0]);
	if (fd_tochild)
		close_noerr(tochild[1]);
fail:
	return -1;
}

pid_t pipecmd(int *fd_fromchild, int *fd_tochild, const char *cmd, ...)
{
	pid_t childpid;

	va_list ap;
	va_start(ap, cmd);
	childpid = pipecmdv(fd_fromchild, fd_tochild, cmd, ap);
	va_end(ap);

	return childpid;
}