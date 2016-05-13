# Dockerfile for GroupServer. Taken from the example Dockerfile for
# http://docs.docker.com/examples/postgresql_service/
FROM ubuntu:14.04
MAINTAINER Michael JasonSmith <mpj17@onlinegroups.net>

# Add the PostgreSQL PGP key to verify their Debian packages.
# It should be the same key as https://www.postgresql.org/media/keys/ACCC4CF8.asc
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8

# Add PostgreSQL's repository. It contains the most recent stable release
#     of PostgreSQL, ``9.3``.
RUN echo "deb http://apt.postgresql.org/pub/repos/apt/ precise-pgdg main" > /etc/apt/sources.list.d/pgdg.list

# Install ``python-software-properties``, ``software-properties-common`` and PostgreSQL 9.3
#  There are some warnings (in red) that show up during the build. You can hide
#  them by prefixing each apt-get statement with DEBIAN_FRONTEND=noninteractive
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update &&\
    apt-get install -y python-software-properties software-properties-common \
                       postgresql-9.3 postgresql-client-9.3 libpq-dev \
                       postgresql-contrib-9.3 postgresql postfix sed git \
                       python python-virtualenv python-dev build-essential \
                       redis-server libxslt-dev libjpeg62-dev libwebp-dev

# Adjust PostgreSQL configuration so that remote connections to
# the database are possible, and add ``listen_addresses`` to
# ``/etc/postgresql/9.3/main/postgresql.conf``, and
RUN echo "host all  all    0.0.0.0/0  md5" >> /etc/postgresql/9.3/main/pg_hba.conf &&\
   echo "listen_addresses='*'" >> /etc/postgresql/9.3/main/postgresql.conf
# Set the maximum number of prepared transactions
RUN sed -i -e 's/^.*max_prepared_transactions = .*$/max_prepared_transactions = 10 \t\t# Set by GroupServer install script/' /etc/postgresql/9.3/main/postgresql.conf
#
# Set up the GroupServer databases
#
# Run the rest of the commands as the ``postgres`` user created by
# the ``postgres-9.3`` package when it was ``apt-get installed``
USER postgres
# Create the "relational database" that stores most of the GroupServer data.
RUN /etc/init.d/postgresql start &&\
    createuser -d -S -R -l gsadmin &&\
    psql -q -c "ALTER USER gsadmin WITH ENCRYPTED PASSWORD 'ChangeMeToSomethingElse'" &&\
    createdb -Ttemplate0 -EUTF-8 --owner=gsadmin groupserver &&\
    psql -q -c "GRANT ALL PRIVILEGES ON DATABASE groupserver TO gsadmin"
# Create the relstorage database, which holds the ZODB.
RUN /etc/init.d/postgresql start &&\
    createuser -d -S -R -l gszodbadmin &&\
    psql -q -c "ALTER USER gszodbadmin WITH ENCRYPTED PASSWORD 'ChangeMeToSomethingElse'" &&\
    createdb -Ttemplate0 -EUTF-8 --owner=gszodbadmin groupserverzodb &&\
    psql -q -c "GRANT ALL PRIVILEGES ON DATABASE groupserverzodb TO gszodbadmin"
#
# Create a GroupServer user
#
USER root
RUN useradd --system groupserver && \
    mkdir -p /opt/groupserver && \
    chown groupserver.groupserver /opt/groupserver
# Clone the GroupServer buildout code, set up a
# virtual-environment for GroupServer, and run buildout
USER groupserver
RUN git clone https://github.com/groupserver/buildout /opt/groupserver &&\
    virtualenv --python=python2.7 /opt/groupserver &&\
    . /opt/groupserver/bin/activate &&\
    /opt/groupserver/bin/pip install zc.buildout==2.5.0

USER root
RUN  /etc/init.d/postgresql start &&\
     su -c "/opt/groupserver/bin/buildout -N -c /opt/groupserver/buildout.cfg"\
        groupserver

# Add VOLUMEs to allow backup of config, logs and databases
VOLUME  ["/etc/postgresql", "/var/log/postgresql", "/var/lib/postgresql", "/opt/groupserver/parts/log", "/opt/groupserver/parts/instance" ]

# Expose the ports for PostgreSQL and GroupServer
EXPOSE 5432
EXPOSE 8080

# Set the default command to run when starting the container
CMD ["/sbin/init"]

USER groupserver
