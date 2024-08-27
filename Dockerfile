#
# Bungeegum build environment
#
FROM gradle:6.5-jdk8

ENV SDK_HOME /usr/local
RUN apt-get --quiet update --yes
RUN apt-get --quiet install --yes wget tar unzip lib32stdc++6 lib32z1 curl
RUN apt-get --quiet install --yes libqt5widgets5 usbutils

ENV APP_HOME=/app

# android sdk|build-tools|image
ENV ANDROID_TARGET_SDK="android-33" \
    ANDROID_BUILD_TOOLS="30.0.2" \
    ANDROID_SDK_TOOLS="7583922"
ENV ANDROID_SDK_URL https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_TOOLS}_latest.zip
RUN curl -sSL "${ANDROID_SDK_URL}" -o android-sdk-linux.zip \
    && unzip android-sdk-linux.zip -d /opt/android-sdk-linux \
    && rm -rf android-sdk-linux.zip

# Set ANDROID_HOME
ENV ANDROID_HOME /opt/android-sdk-linux
ENV PATH ${ANDROID_HOME}/bin:$PATH


# Update and install using sdkmanager
RUN echo yes | $ANDROID_HOME/cmdline-tools/bin/sdkmanager --sdk_root=${ANDROID_HOME} --licenses
RUN echo yes | $ANDROID_HOME/cmdline-tools/bin/sdkmanager --sdk_root=${ANDROID_HOME} "tools" "platform-tools"
RUN echo yes | $ANDROID_HOME/cmdline-tools/bin/sdkmanager --sdk_root=${ANDROID_HOME} "build-tools;${ANDROID_BUILD_TOOLS}"
RUN echo yes | $ANDROID_HOME/cmdline-tools/bin/sdkmanager --sdk_root=${ANDROID_HOME} "platforms;${ANDROID_TARGET_SDK}"

RUN chmod -R 777 $ANDROID_HOME
RUN chmod -R 777 /home/gradle
ENV _JAVA_OPTIONS=-Duser.home=/home/gradle
ENV GRADLE_USER_HOME = /home/gradle
ENV PATH ${SDK_HOME}/bin:$PATH
