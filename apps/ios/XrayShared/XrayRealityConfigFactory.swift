import Foundation

struct XrayRealityConfigError: Error, Equatable {
    let code: String
}

enum XrayRealityConfigFactory {
    static func make(
        request: XrayRuntimeRequest,
        tunFileDescriptor: Int32
    ) throws -> String {
        try request.validate()
        guard tunFileDescriptor >= 0 else {
            throw XrayRealityConfigError(code: "invalid_tun_fd")
        }

        let transport = request.transport
        let configuration: [String: Any] = [
            "log": [
                "loglevel": "warning"
            ],
            "env": [
                "xray.tun.fd": String(tunFileDescriptor)
            ],
            "inbounds": [
                [
                    "tag": "tun-in",
                    "port": 0,
                    "protocol": "tun",
                    "settings": [
                        "mtu": request.mtu,
                        "autoOutboundsInterface": "auto"
                    ]
                ]
            ],
            "outbounds": [
                [
                    "tag": "proxy",
                    "protocol": "vless",
                    "settings": [
                        "vnext": [
                            [
                                "address": transport.endpointHost,
                                "port": transport.endpointPort,
                                "users": [
                                    [
                                        "id": transport.clientId,
                                        "flow": "xtls-rprx-vision",
                                        "encryption": "none",
                                        "level": 0
                                    ]
                                ]
                            ]
                        ]
                    ],
                    "streamSettings": [
                        "network": "raw",
                        "security": "reality",
                        "realitySettings": [
                            "fingerprint": "chrome",
                            "serverName": transport.serverName,
                            "publicKey": transport.publicKey,
                            "shortId": transport.shortId.lowercased(),
                            "spiderX": ""
                        ]
                    ]
                ],
                [
                    "tag": "block",
                    "protocol": "blackhole"
                ]
            ],
            "routing": [
                "domainStrategy": "AsIs",
                "rules": [
                    [
                        "type": "field",
                        "inboundTag": ["tun-in"],
                        "outboundTag": "proxy"
                    ]
                ]
            ]
        ]

        guard JSONSerialization.isValidJSONObject(configuration) else {
            throw XrayRealityConfigError(code: "xray_config_invalid_json")
        }
        let data = try JSONSerialization.data(
            withJSONObject: configuration,
            options: [.sortedKeys]
        )
        guard let text = String(data: data, encoding: .utf8) else {
            throw XrayRealityConfigError(code: "xray_config_not_utf8")
        }

        guard !text.contains("privateKey"),
              !text.contains("NODE_CONTROL_SECRET"),
              !text.contains("VPN_NODE_TOKEN")
        else {
            throw XrayRealityConfigError(code: "forbidden_secret_material")
        }
        return text
    }
}
