/** @type {import('next').NextConfig} */
const nextConfig = {
    images: {
        remotePatterns: [
            { 
                protocol: 'http',
                hostname: 'localhost', 
            },
            {
                protocol: 'https',
                hostname: 'epk.tapped.ai',
            },
            {
                protocol: 'https',
                hostname: 'getmusicepk.com',
            },
            {
                protocol: 'https',
                hostname: 'www.getmusicepk.com',
            },
            {
                protocol: 'https',
                hostname: 'firebasestorage.googleapis.com',
            },
        ],
    }
}

module.exports = nextConfig
