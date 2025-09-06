/* eslint-disable jsx-a11y/alt-text */
/* eslint-disable @next/next/no-img-element */
import { EpkPayload } from "@/types/epk_payload";
import { getURL } from "@/utils/url";

const qrCodeDimensions = 75;

export default function FunkyTheme({
    artistName,
    bio,
    imageUrl,
    jobs,
    tappedRating,
    tiktokHandle,
    instagramHandle,
    twitterHandle,
    phoneNumber,
    location,
    notableSongs,
}: EpkPayload) {
    const qrCodeUrl = `https://api.qrserver.com/v1/create-qr-code/?size=${
        qrCodeDimensions
    }x${
        qrCodeDimensions
    }&bgcolor=010F16&color=cbd5e1&data=https://instagram.com/${
        instagramHandle
    }`
    const ratingString = (tappedRating === null || tappedRating === '') ? "Unranked on Tapped" : `${tappedRating} / 5 stars on Tapped `
    return (
        <div
            style={{
                height: '100%',
                width: '100%',
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                color: 'white',
                padding: '20px',
                paddingTop: '60px',
                position: 'relative',
            }}
        >
            <div style={{
                display: 'flex',
                position: 'absolute',
                top: 0,
                left: 0,
                right: 0,
                bottom: 0,
                // zIndex: -1,
            }}>
                <div style={{
                    backgroundColor: '#e97451',
                    width: '100%',
                    height: '100%',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                }}>
                    <div style={{
                        backgroundColor: '#eedc82',
                        width: '70%',
                        height: '80%',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        borderRadius: 10
                    }}>
                        <div style={{
                            backgroundColor: 'orange',
                            width: '60%',
                            height: '70%',
                            borderRadius: 10
                        }} />
                    </div>
                </div>
            </div>
            <div style={{display: 'flex', flexDirection: 'row', justifyContent: 'space-between'}}>
              <div style={{
                display: 'flex', 
                flexDirection: 'column', 
                backgroundColor: '#fbf5df',
                borderRadius: '5%',
                paddingLeft: 20,
                paddingRight: 20,
                marginRight: 20,
                color: '#ff4433',
              }}
            >
                <h1
                    style={{
                        display: 'flex',
                        fontSize: '48px',
                        margin: '4px',
                        marginTop: '12px'
                    }}
                >
                    {artistName}
                </h1>
                <div style={{display: 'flex', flexDirection: 'column'}}>
                    <div style={{display: 'flex', flexDirection: 'column'}}>
                        <div style={{display: 'flex'}}>
                            <p style={{fontSize: '36px', fontFamily: 'JosefinSansBold', margin: '4px', marginBottom: '18px'}}>Location</p>
                        </div>
                        <div style={{display: 'flex'}}>
                            <img src={getURL('/location_pin_icon.png')} alt="Location icon" style={{ width: '20px', height: '20px', marginTop: '4px' }} />
                            <p style={{fontSize: '26px', fontFamily: 'JosefinSansItalic', margin: '4px'}}>{location}</p>
                        </div>
                    </div>
                    <div style={{display: 'flex', flexDirection: 'column'}}>
                        <div style={{display: 'flex'}}>
                            <p style={{fontSize: '36px', fontFamily: 'JosefinSansBold', margin: '4px'}}>Rating</p>
                        </div>
                        <div style={{display: 'flex'}}>
                            <p style={{fontSize: '26px', fontFamily: 'JosefinSansItalic', margin: '4px'}}>{ratingString}</p>
                        </div>
                    </div>
                    <div style={{display: 'flex', flexDirection: 'column'}}>
                        <div style={{display: 'flex'}}>
                            <p style={{fontSize: '36px', fontFamily: 'JosefinSansBold', margin: '4px'}}>Profession</p>
                        </div>
                        <div style={{display: 'flex'}}>
                            <p style={{fontSize: '26px', fontFamily: 'JosefinSansItalic', margin: '4px'}}>{jobs.join(', ')}</p>
                        </div>
                    </div>
                </div>
            </div>
            <div
                style={{
                    display: 'flex',
                    position: 'relative',
                    width: 400,
                    height: 400,
                }}
            >
                <div
                    style={{
                        display: 'flex',
                        justifyContent: 'center',
                        alignItems: 'center',
                        width: '100%',
                        position: 'relative',
                        overflow: 'hidden',
                        borderRadius: '5%',
                    }}
                >
                    <img
                        src={imageUrl}
                        alt="headshot of author"
                        width={400}
                        height={400}
                        style={{
                            objectFit: 'cover',
                        }}
                    />
                </div>
            </div>
            </div>
            <div style={{
                    display: 'flex',
                    position: 'absolute',
                    top: '44%',

                    backgroundColor: '#e3963e',
                    borderRadius: 10,
                    width: '90%',
                    height: '300px',
                }}
            ></div>
            <div
                style={{
                    display: 'flex',
                    flexDirection: 'column',
                    width: '100%',
                    marginTop: 50,
                    borderRadius: 10,
                    paddingLeft: 20,
                    paddingRight: 20,
                    paddingTop: 20,
                    paddingBottom: 20,
                    backgroundColor: '#ffc000',
                    color: 'black',
                    height: '265px',
                    wordWrap: 'break-word',
                    whiteSpace: 'normal',
                    hyphens: 'auto',
                    overflowWrap: 'break-word',
                }}
            >
                <p style={{ fontSize: 18, }}>
                    {bio}
                </p>
            </div>
            <div style={{
                    display: 'flex',
                    position: 'absolute',
                    bottom: '7%',
                    backgroundColor: '#e3963e',
                    borderRadius: 10,
                    width: '100%',
                    height: '290px',
                }}
            ></div>
            <div
                style={{
                    display: 'flex',
                    flexDirection: 'row',
                    position: 'absolute',
                    bottom: '4%',
                    marginTop: 20,
                    justifyContent: 'space-between',
                    width: '100%',
                    padding: '0 20px'
                }}
            >
                <div style={{ 
                    display: 'flex', 
                    flexDirection: 'row', 
                    justifyContent: 'space-between',
                    backgroundColor: '#ffc000',
                    borderRadius: 10,
                    alignItems: 'center',
                    width: '100%',
                    marginRight: '20px',
                }}>
                    <div style={{ 
                      display: 'flex', 
                      color: 'white',
                      flexDirection: 'column',
                      alignItems: 'center',
                      flex: 1 }}
                    >
                    <div style={{display: 'flex', flexDirection: 'row', justifyContent: 'space-between'}}>
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
                                    width: 80,
                                    height: 80,
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
                    <div style={{ display: 'flex', flexDirection: 'column', justifyContent: 'center', alignItems: 'center', width: '800px'}}>
                        {/* {(spotifyId !== undefined && spotifyId !== null && spotifyId !== '')
                            ? < div style={{
                                display: 'flex',
                                margin: '4px',
                                alignItems: 'center',
                                justifyContent: 'center',
                                padding: 5,
                                borderRadius: 10,
                            }}>
                                <p style={{ marginLeft: '20px', fontSize: '20px', marginTop: '0px', marginBottom: '0px', fontFamily: 'JosefinSansBold' }}>
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
                                <p style={{ marginLeft: '20px', fontSize: '20px', marginTop: '0px', marginBottom: '0px', fontFamily: 'JosefinSansBold' }}>
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
                                <p style={{ marginLeft: '20px', fontSize: '20px', marginTop: '0px', marginBottom: '0px', fontFamily: 'JosefinSansBold'  }}>
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
                                <p style={{ marginLeft: '20px', fontSize: '20px', marginTop: '0px', marginBottom: '30px', fontFamily: 'JosefinSansBold' }}>
                                    @{twitterHandle}
                                </p>
                            </div>
                            : null}
                    </div>
                    </div>
                    <div style={{ 
                        display: 'flex', 
                        flexDirection: 'column', 
                        justifyContent: 'center', 
                        alignItems: 'center', 
                        borderRadius: 10, 
                        color: 'black', 
                        paddingLeft: 5, 
                        paddingRight: 5,
                        marginTop: 50, 
                        marginBottom: 90,
                        flex: 1,
                      }}>
                            <h1 style={{fontFamily: 'JosefinSansBold', fontSize: '48px', margin: '4px', color: 'black'}}>Top Songs</h1>
                            <div style={{display: 'flex', flexDirection: 'column', margin: '4px'}}>
                                <div style={{display: 'flex', flexDirection: 'row'}}>
                                    <div style={{display: 'flex'}}>
                                        <p style={{fontSize: '26px', fontFamily: 'JosefinSans', margin: '4px'}}>{notableSongs[0].title} |</p>
                                    </div>
                                    <div style={{display: 'flex'}}>
                                        <p style={{fontSize: '24px', fontFamily: 'JosefinSansItalic', margin: '4px'}}>{notableSongs[0].plays} plays</p>
                                    </div>
                                </div>
                                <div style={{display: 'flex', flexDirection: 'row'}}>
                                    <div style={{display: 'flex'}}>
                                        <p style={{fontSize: '26px', fontFamily: 'JosefinSans', margin: '4px'}}>{notableSongs[1].title} |</p>
                                    </div>
                                    <div style={{display: 'flex'}}>
                                        <p style={{fontSize: '24px', fontFamily: 'JosefinSansItalic', margin: '4px'}}>{notableSongs[1].plays} plays</p>
                                    </div>
                                </div>
                                <div style={{display: 'flex', flexDirection: 'row'}}>
                                    <div style={{display: 'flex'}}>
                                        <p style={{fontSize: '26px', fontFamily: 'JosefinSans', margin: '4px'}}>{notableSongs[2].title} |</p>
                                    </div>
                                    <div style={{display: 'flex'}}>
                                        <p style={{fontSize: '24px', fontFamily: 'JosefinSansItalic', margin: '4px'}}>{notableSongs[2].plays} plays</p>
                                    </div>
                                </div>
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
        </div >
    );
}