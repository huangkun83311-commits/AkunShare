#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <string.h>
#include <ifaddrs.h>
#include <errno.h>

#define PORT 8383

// 1. 获取设备名称 (优先用户设置的名称)
static NSString* getDeviceName() {
    NSString *deviceName = [[UIDevice currentDevice] name];
    if (!deviceName || deviceName.length == 0) {
        deviceName = [[NSProcessInfo processInfo] hostName];
    }
    return deviceName;
}

// 2. 获取局域网 IP (优先 WiFi)
static NSString* getLocalIPAddress() {
    NSString *address = @"0.0.0.0";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = getifaddrs(&interfaces);
    
    if (success == 0) {
        temp_addr = interfaces;
        while(temp_addr != NULL) {
            if(temp_addr->ifa_addr && temp_addr->ifa_addr->sa_family == AF_INET) {
                NSString *name = [NSString stringWithUTF8String:temp_addr->ifa_name];
                // 优先 en0 (WiFi) 或 pdp_ip (蜂窝)
                if ([name isEqualToString:@"en0"] || [name hasPrefix:@"pdp_ip"]) {
                     NSString *tempIP = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                     if (![tempIP isEqualToString:@"127.0.0.1"]) {
                         address = tempIP;
                         // 找到 WiFi IP 直接返回
                         if ([name isEqualToString:@"en0"] && [address hasPrefix:@"192.168."]) {
                             break;
                         }
                     }
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
        // ⚠️ 重要：必须释放内存
        freeifaddrs(interfaces);
    }
    return address;
}

static void startUDPServer() {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        int sock = socket(AF_INET, SOCK_DGRAM, 0);
        if (sock < 0) {
            NSLog(@"[AkunShare] ❌ Socket Failed (errno: %d)", errno);
            return;
        }

        int opt = 1;
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
        setsockopt(sock, SOL_SOCKET, SO_REUSEPORT, &opt, sizeof(opt));

        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = INADDR_ANY;
        addr.sin_port = htons(PORT);

        if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
            NSLog(@"[AkunShare] ❌ Bind Port %d Failed (errno: %d)", PORT, errno);
            close(sock);
            return;
        }

        NSLog(@"[AkunShare] ✅ Server Started on Port %d", PORT);

        char buffer[1024];
        struct sockaddr_in clientAddr;
        socklen_t clientLen = sizeof(clientAddr);

        while (YES) {
            ssize_t len = recvfrom(sock, buffer, sizeof(buffer) - 1, 0, (struct sockaddr *)&clientAddr, &clientLen);
            if (len > 0) {
                buffer[len] = '\0'; 
                NSString *message = [NSString stringWithUTF8String:buffer];
                NSString *senderIP = [NSString stringWithUTF8String:inet_ntoa(clientAddr.sin_addr)];
                
                // --- 逻辑 1: 处理 PING ---
                if ([message isEqualToString:@"PING"]) {
                    NSString *deviceName = getDeviceName();
                    NSString *myIP = getLocalIPAddress();
                    
                    NSString *replyMsg = [NSString stringWithFormat:@"PONG|%@|%@", deviceName, myIP];
                    const char *replyCStr = [replyMsg UTF8String];
                    
                    sendto(sock, replyCStr, strlen(replyCStr), 0, (struct sockaddr *)&clientAddr, clientLen);
                    // 正常请求才打印日志，清爽一点
                    NSLog(@"[AkunShare] 🏓 Replied to %@: %@", senderIP, deviceName);
                    continue; 
                }

                // --- 逻辑 2: 处理 OPEN_URL ---
                if ([message hasPrefix:@"OPEN_URL|"]) {
                    NSString *urlString = [message substringFromIndex:9];
                    if (urlString.length == 0) continue;
                    
                    NSLog(@"[AkunShare] 🚀 Opening: %@", urlString);
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSURL *url = [NSURL URLWithString:urlString];
                        if (url) {
                            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
                                NSLog(@"[AkunShare] 📱 Open Result: %@", success ? @"Success" : @"Failed");
                            }];
                        }
                    });
                }
            }
        }
        close(sock);
    });
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    NSLog(@"[AkunShare] 📱 Service Initialized");
    startUDPServer();
}
%end