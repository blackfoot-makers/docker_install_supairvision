FROM ros:indigo

# Arguments
ARG user
ARG uid
ARG home
ARG workspace
ARG shell

# Basic Utilities
RUN apt-get -y update && apt-get install -y zsh screen tree sudo ssh synaptic gawk make git curl cmake

# Latest X11 / mesa GL
RUN apt-get install -y\
  xserver-xorg-dev-lts-wily\
  libegl1-mesa-dev-lts-wily\
  libgl1-mesa-dev-lts-wily\
  libgbm-dev-lts-wily\
  mesa-common-dev-lts-wily\
  libgles2-mesa-lts-wily\
  libwayland-egl1-mesa-lts-wily\
  libopenvg1-mesa

# Dependencies required to build rviz
RUN apt-get install -y\
  qt4-dev-tools\
  libqt5core5a libqt5dbus5 libqt5gui5 libwayland-client0\
  libwayland-server0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1\
  libxcb-render-util0 libxcb-util0 libxcb-xkb1 libxkbcommon-x11-0\
  libxkbcommon0


# The rest of ROS-desktop
RUN apt-get install -y ros-indigo-desktop-full

# Dependencies for MAVProxy
RUN apt-get install -y g++ python-pip python-matplotlib python-serial python-wxgtk2.8 python-scipy python-opencv python-numpy python-pyparsing ccache realpath libopencv-dev

# Install Aruco
RUN wget http://34.251.139.238/aruco-1.3.0.tgz && \
  tar -xzf aruco-1.3.0.tgz && cd aruco-1.3.0 && \
  mkdir build && cd build && cmake .. && make && \
  make install

# Additional development tools
RUN apt-get install -y x11-apps build-essential

# Get Ardupilot
RUN mkdir -p "${workspace}/simulation" && cd "${workspace}/simulation" && \
  git clone https://github.com/erlerobot/ardupilot -b gazebo && \
  git clone git://github.com/tridge/jsbsim.git && \
  apt-get install -y libtool automake autoconf libexpat1-dev && \
  cd jsbsim && ./autogen.sh --enable-libraries && make && make install

# Init ROS
RUN rm -rf /etc/ros/rosdep/sources.list.d/*
RUN rosdep init
RUN rosdep update

# More ROS dependencies
RUN apt-get install -y python-rosinstall          \
                    ros-indigo-octomap-msgs    \
                    ros-indigo-joy             \
                    ros-indigo-geodesy         \
                    ros-indigo-octomap-ros     \
                    ros-indigo-mavlink         \
                    ros-indigo-control-toolbox \
                    ros-indigo-transmission-interface \
                    ros-indigo-joint-limits-interface \
                    unzip

# Install gazebo
RUN sh -c 'echo "deb http://packages.osrfoundation.org/gazebo/ubuntu-stable `lsb_release -cs` main" > /etc/apt/sources.list.d/gazebo-stable.list'
RUN wget http://packages.osrfoundation.org/gazebo.key -O - | apt-key add -
RUN apt-get update
RUN apt-get remove -y .*gazebo.* '.*sdformat.*' '.*ignition-math.*' && apt-get update && apt-get install -y gazebo7 libgazebo7-dev drcsim7
RUN apt-get autoremove -y

# The rest of MavProxy
RUN pip2 install pymavlink==2.0.6 catkin_pkg --upgrade
RUN pip2 install MAVProxy==1.5.2
  
# Install dronekit
RUN pip2 install dronekit

# Some more packages
RUN pip2 install sympy

# Create model directory for eolienne model
RUN mkdir -p "${home}/.gazebo/models"

# Copy ssh congiguration
RUN mkdir "${home}/.ssh"
COPY .ssh "${home}/.ssh"

# Make SSH available
EXPOSE 22

# Clone user into docker image and set up X11 sharing
RUN \
  echo "${user}:x:${uid}:${uid}:${user},,,:${home}:${shell}" >> /etc/passwd && \
  echo "${user}:x:${uid}:" >> /etc/group && \
  echo "${user} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${user}" && \
  chmod 0440 "/etc/sudoers.d/${user}"

RUN chown -R "${user}" "${home}" && chown -R "${user}" "${workspace}"

# Mount the user's home directory
VOLUME "${workspace}/simulation"
VOLUME "${home}/.ssh"

RUN apt-get install libxslt1-dev

# Switch to user
USER "${user}"

RUN pip2 install lxml --user

# Install suparivision
## Clone depot
RUN cd "${workspace}" && \
 git clone git@bitbucket.org:maxbou/supairvision.git

WORKDIR "/${workspace}/supairvision"

## Copy gazebo models
RUN cp -rf ./GazeboModels/eolienne $home/.gazebo/models/
RUN sed -i "s~/home/jesro~${home}~g"  $home/.gazebo/models/eolienne/model.sdf

## Initialize ros workspace
RUN mkdir -p supairvision_ws/src
WORKDIR supairvision_ws

RUN . "/opt/ros/indigo/setup.sh" && cd src && catkin_init_workspace && \
  cd ../ && pwd && \
  catkin_make

## Get additional packages
RUN cd src && \
  git clone "git@bitbucket.org:maxbou/supairvision.git" && \
  git clone https://github.com/tu-darmstadt-ros-pkg/hector_gazebo/ && \
  git clone https://github.com/erlerobot/rotors_simulator -b sonar_plugin && \
  git clone https://github.com/PX4/mav_comm.git && \
  git clone https://github.com/ethz-asl/glog_catkin.git && \
  git clone https://github.com/catkin/catkin_simple.git && \
  git clone https://github.com/erlerobot/mavros.git && \
  git clone https://github.com/ros-simulation/gazebo_ros_pkgs.git -b indigo-devel && \
# Add Python and C++ examples
  git clone https://github.com/erlerobot/gazebo_cpp_examples && \
  git clone https://github.com/erlerobot/gazebo_python_examples

  
## Install new packages  
RUN /bin/bash -c '. ./devel/setup.bash; catkin_make -j 4 --pkg mav_msgs mavros_msgs gazebo_msgs'
RUN /bin/bash -c '. ./devel/setup.bash; catkin_make -j 4'

# Remove wromg version of mavlink and install good one
RUN sudo apt-get remove --purge -y ros-indigo-mavlink
RUN pip2 install pymavlink==2.0.6

## Mount newly created directories
VOLUME "${home}/.gazebo"
VOLUME "${workspace}/supairvision"


# This is required for sharing Xauthority
ENV QT_X11_NO_MITSHM=1
ENV CATKIN_TOPLEVEL_WS="${workspace}/devel"
# Switch to the workspace
WORKDIR ${workspace}
