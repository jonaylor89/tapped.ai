/* eslint-disable jsx-a11y/alt-text */
/* eslint-disable @next/next/no-img-element */
import { EpkPayload } from "@/types/epk_payload";
import { getURL } from "@/utils/url";

const maxSongTitleLength = 15;
const qrCodeDimensions = 75;

const truncatedSongTitle = (title: string) => {
    if (title.length > maxSongTitleLength) {
        return title.substring(0, maxSongTitleLength) + '...';
    }
    return title;

}

export default function TappedTheme({
    artistName,
    bio,
    jobs,
    imageUrl,
    tappedRating,
    tiktokHandle,
    instagramHandle,
    twitterHandle,
    phoneNumber,
    location,
    notableSongs,
}: EpkPayload) {
    const qrCodeUrl = `https://api.qrserver.com/v1/create-qr-code/?size=${qrCodeDimensions
        }x${qrCodeDimensions
        }&bgcolor=010F16&color=cbd5e1&data=https://instagram.com/${instagramHandle
        }`
    const ratingString = (tappedRating === null || tappedRating === '') ? "Unranked on Tapped" : `${tappedRating} / 5 stars on Tapped `
    const socialsDivHeight = (instagramHandle !== '' && twitterHandle !== '' && tiktokHandle !== '') ? '220px' : '200px'
    return (
        <div
            style={{
                height: '100%',
                width: '100%',
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                backgroundColor: '#15242d',
                color: 'white',
                padding: '20px',
                paddingTop: '60px',
                position: 'relative',
            }}
        >
            <div
                style={{
                    display: 'flex',
                    position: 'absolute',
                    overflow: 'hidden',
                    // zIndex: -1,
                    top: '-5%',
                    left: '-40%',
                    width: '900px',
                    height: '900px',
                }}
            >
                <img
                    src={getURL('/blue_circle_1.png')}
                    alt="Blurred Circle 1"
                    width='900px'
                    height='900px'
                    style={{
                        objectFit: 'cover',
                    }}
                />
            </div>
            <div
                style={{
                    display: 'flex',
                    position: 'absolute',
                    overflow: 'hidden',
                    // zIndex: -1,
                    top: '75%',
                    right: '-30%',
                    width: '800px',
                    height: '800px',
                }}
            >
                <img
                    src={getURL('/blue_circle_1.png')}
                    alt="Blurred Circle 2"
                    width='800px'
                    height='800px'
                    style={{
                        objectFit: 'cover',
                    }}
                />
            </div>
            <div
                style={{
                    display: 'flex',
                    position: 'absolute',
                    overflow: 'hidden',
                    // zIndex: -1,
                    bottom: '70%',
                    left: '95%',
                    width: '700px',
                    height: '700px',
                    transform: 'translateX(-50%)',
                }}
            >
                <img
                    src={getURL('/blue_circle_3.png')}
                    alt="Blurred Circle 3"
                    width='700px'
                    height='700px'
                    style={{
                        objectFit: 'cover',
                    }}
                />
            </div>
            <div style={{
                display: 'flex',
                position: 'absolute',
                overflow: 'hidden',
                bottom: '2%',
                left: '2%',
            }}>
                <img
                    src={qrCodeUrl}
                    width={qrCodeDimensions}
                    height={qrCodeDimensions}
                />
            </div>
            <div
                style={{
                    display: 'flex',
                    position: 'relative',
                    width: 512,
                    height: 512,
                }}
            >
                <div
                    style={{
                        display: 'flex',
                        width: '100%',
                        height: '100%',
                        overflow: 'hidden',
                        borderRadius: 10,
                    }}
                >
                    <img
                        src={imageUrl}
                        alt="headshot of author"
                        width={512}
                        height={512}
                        style={{
                            objectFit: 'cover',
                        }}
                    />
                    {/* <div
                        style={{
                            display: 'flex',
                            position: 'absolute',
                            bottom: 0,
                            left: 0,
                            right: 0,
                            height: '50%',
                            backgroundImage: 'linear-gradient(transparent, #15242d)',
                        }}
                    ></div> */}
                </div>

                <h1
                    style={{
                        display: 'flex',
                        position: 'absolute',
                        bottom: 10,
                        left: '50%',
                        transform: 'translateX(-50%)',
                        padding: '5px 10px',
                        fontSize: '48px',
                    }}
                >
                    {artistName}
                </h1>
            </div>

            <div style={{
                display: 'flex',
                position: 'absolute',
                right: '0%',
                top: '10%',
                flexDirection: 'column',
                backgroundColor: '#5f9ea0',
                borderTopLeftRadius: 10,
                borderBottomLeftRadius: 10,
                paddingLeft: '10px',
                paddingRight: '10px',
            }}
            >
                <div style={{ display: 'flex', flexDirection: 'column' }}>
                    <div style={{ display: 'flex', flexDirection: 'row', alignItems: 'center' }}>
                        <div style={{ display: 'flex' }}>
                            <p style={{ fontSize: '28px', margin: '4px', fontFamily: 'InterBold' }}>Location |</p>
                        </div>
                        <div style={{ display: 'flex' }}>
                            <img src={getURL('/location_pin_icon.png')} alt="Location icon" style={{ width: '20px', height: '20px', marginTop: '4px' }} />
                            <p style={{ fontSize: '20px', margin: '4px', fontFamily: 'InterItalic' }}>{location}</p>
                        </div>
                    </div>
                    <div style={{ display: 'flex', flexDirection: 'row', alignItems: 'center' }}>
                        <div style={{ display: 'flex' }}>
                            <p style={{ fontSize: '28px', margin: '4px', fontFamily: 'InterBold' }}>Rating |</p>
                        </div>
                        <div style={{ display: 'flex' }}>
                            <p style={{ fontSize: '20px', margin: '4px', fontFamily: 'InterItalic' }}>{ratingString}</p>
                        </div>
                    </div>
                    <div style={{ display: 'flex', flexDirection: 'row', alignItems: 'center' }}>
                        <div style={{ display: 'flex' }}>
                            <p style={{ fontSize: '28px', margin: '4px', fontFamily: 'InterBold' }}>Profession |</p>
                        </div>
                        <div style={{ display: 'flex' }}>
                            <p style={{ fontSize: '20px', margin: '4px', fontFamily: 'InterItalic' }}>{jobs.join(', ')}</p>
                        </div>
                    </div>
                </div>
            </div>

            <div style={{
                display: 'flex',
                position: 'absolute',
                left: '0%',
                top: '53%',
                backgroundColor: '#5f9ea0',
                borderTopRightRadius: 10,
                borderBottomRightRadius: 10,
                height: socialsDivHeight,
                width: '50%'
            }}
            ></div>

            <div
                style={{
                    display: 'flex',
                    flexDirection: 'row',
                    marginTop: 40,
                    justifyContent: 'space-between',
                    width: '100%',
                    padding: '0 20px',
                }}
            >
                <div style={{
                    display: 'flex',
                    flexDirection: 'column',
                    marginRight: '20px',
                    flex: 1,
                    minWidth: 0,
                }}>
                    <div style={{
                        display: 'flex',
                        flexDirection: 'row',
                        justifyContent: 'space-between'
                    }}>
                        <div
                            style={{
                                display: 'flex',
                                flexDirection: 'column',
                                justifyContent: 'center',
                            }}
                        >
                            <img
                                src={getURL('/spotify_icon_white.png')}
                                alt="spotify icon"
                                width={80}
                                height={80}
                                style={{
                                    objectFit: 'cover',
                                    marginBottom: '5px',

                                }}
                            />
                        </div>
                        <div
                            style={{
                                display: 'flex',
                                flexDirection: 'column',
                                justifyContent: 'center',
                            }}
                        >
                            <img
                                src={getURL('/instagram_icon_white.png')}
                                alt="instagram icon"
                                width={50}
                                height={50}
                                style={{
                                    objectFit: 'cover',
                                    marginBottom: '5px',
                                    width: 50,
                                    height: 50,
                                }}
                            />
                        </div>
                        <div
                            style={{
                                display: 'flex',
                                flexDirection: 'column',
                                justifyContent: 'center',
                            }}
                        >
                            <img
                                src={getURL('/tiktok_icon_white.png')}
                                alt="tiktok icon"
                                width={50}
                                height={50}
                                style={{
                                    objectFit: 'cover',
                                    marginBottom: '5px',
                                    width: 50,
                                    height: 50,
                                }}
                            />
                        </div>
                        <div
                            style={{
                                display: 'flex',
                                flexDirection: 'column',
                                justifyContent: 'center',
                                marginRight: '50px',
                            }}
                        >
                            <img
                                src={getURL("/twitter_icon_white.png")}
                                alt="twitter icon"
                                width={50}
                                height={50}
                                style={{
                                    objectFit: 'cover',
                                    marginBottom: '5px',
                                }}
                            />
                        </div>
                    </div>
                    <div style={{ display: 'flex', flexDirection: 'column' }}>
                        {/* {(spotifyId !== undefined && spotifyId !== null && spotifyId !== '')
                            ? < div style={{
                                display: 'flex',
                                margin: '4px',
                                alignItems: 'center',
                                justifyContent: 'center',
                                padding: 5,
                                borderRadius: 10,
                            }}>
                                <p style={{ marginLeft: '20px', fontSize: '20px', marginTop: '0px', marginBottom: '0px', fontFamily: 'InterBold' }}>
                                    open.spotify.com/artist/{spotifyId}
                                </p>
                            </div>
                            : null} */}
                        {(instagramHandle !== undefined && instagramHandle !== null && instagramHandle !== '')
                            ? <div style={{
                                display: 'flex',
                                alignItems: 'center',
                                margin: '4px',
                                paddingLeft: 5,
                                paddingRight: 5,
                                borderRadius: 10,
                            }}>
                                <p style={{ marginLeft: '20px', fontSize: '20px', marginTop: '0px', marginBottom: '0px', fontFamily: 'InterBold' }}>
                                    @{instagramHandle}
                                </p>
                            </div>
                            : null}

                        {(tiktokHandle !== undefined && tiktokHandle !== null && tiktokHandle !== '')
                            ? <div style={{
                                display: 'flex',
                                alignItems: 'center',
                                margin: '4px',
                                paddingLeft: 5,
                                paddingRight: 5,
                                borderRadius: 10,
                            }}>
                                <p style={{ marginLeft: '20px', fontSize: '20px', marginTop: '0px', marginBottom: '0px', fontFamily: 'InterBold' }}>
                                    @{tiktokHandle}
                                </p>
                            </div>
                            : null}

                        {(twitterHandle !== undefined && twitterHandle !== null && twitterHandle !== '')
                            ? <div style={{
                                display: 'flex',
                                alignItems: 'center',
                                margin: '4px',
                                paddingLeft: 5,
                                paddingRight: 5,
                                borderRadius: 10,
                            }}>
                                <p style={{ marginLeft: '20px', fontSize: '20px', marginTop: '0px', paddingBottom: '20px', fontFamily: 'InterBold' }}>
                                    @{twitterHandle}
                                </p>
                            </div>
                            : null}
                    </div >
                </div >

                <div
                    style={{
                        display: 'flex',
                        flexDirection: 'column',
                        borderRadius: 10,
                        flex: 1,
                        minWidth: 0,
                    }}
                >
                    <h1 style={{
                        color: '#63b2fd',
                        margin: '4px',
                        fontFamily: 'InterBold',
                    }}>
                        Who is {artistName}?
                    </h1>
                    <p style={{
                        textAlign: 'start',
                        fontSize: 16,
                        color: 'white',
                    }}>
                        {bio}
                    </p>
                </div>
            </div >
            <div style={{
                display: 'flex',
                flexDirection: 'column',
                justifyContent: 'center',
                alignItems: 'center',
                borderRadius: 10,
                color: '#63b2fd',
                paddingLeft: 4,
                paddingRight: 4,
            }}>
                <h1 style={{ fontFamily: 'InterBold', fontSize: '48px', margin: '4px' }}>Top Songs</h1>
                <div style={{ display: 'flex', flexDirection: 'column', margin: '4px' }}>
                    <div style={{ display: 'flex', flexDirection: 'row' }}>
                        <div style={{ display: 'flex' }}>
                            <p style={{ fontSize: '26px', fontFamily: 'Inter', margin: '4px 0px' }}>{truncatedSongTitle(notableSongs[0].title)} |</p>
                        </div>
                        <div style={{ display: 'flex' }}>
                            <p style={{ fontSize: '24px', fontFamily: 'InterItalic', margin: '4px' }}>{notableSongs[0].plays} plays</p>
                        </div>
                    </div>
                    <div style={{ display: 'flex', flexDirection: 'row' }}>
                        <div style={{ display: 'flex' }}>
                            <p style={{ fontSize: '26px', fontFamily: 'Inter', margin: '4px 0px' }}>{truncatedSongTitle(notableSongs[1].title)} |</p>
                        </div>
                        <div style={{ display: 'flex' }}>
                            <p style={{ fontSize: '24px', fontFamily: 'InterItalic', margin: '4px' }}>{notableSongs[1].plays} plays</p>
                        </div>
                    </div>
                    <div style={{ display: 'flex', flexDirection: 'row' }}>
                        <div style={{ display: 'flex' }}>
                            <p style={{ fontSize: '26px', fontFamily: 'Inter', margin: '4px 0px' }}>{truncatedSongTitle(notableSongs[2].title)} |</p>
                        </div>
                        <div style={{ display: 'flex' }}>
                            <p style={{ fontSize: '24px', fontFamily: 'InterItalic', margin: '4px' }}>{notableSongs[2].plays} plays</p>
                        </div>
                    </div>
                </div>
            </div>
            <div style={{
                display: 'flex',
                position: 'absolute',
                bottom: '1%',
            }}
            >
                {(phoneNumber !== undefined && phoneNumber !== null && phoneNumber !== '')
                    ? <p>agent contact: {phoneNumber}</p>
                    : null}
            </div>
        </div >
    );
}