/* eslint-disable jsx-a11y/alt-text */
/* eslint-disable @next/next/no-img-element */
import { EpkPayload } from "@/types/epk_payload";
import { getURL } from "@/utils/url";

const qrCodeDimensions = 75;

export default function MinimalistTheme({
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
                backgroundColor: '#fdf6e4',
                color: 'black',
                padding: '20px',
                paddingTop: '60px',
                position: 'relative',
            }}
        >
            <div style={{display: 'flex', flexDirection: 'row', marginBottom: '25px', alignItems: 'flex-start', width: '100%',}}>
              <div
                  style={{
                      display: 'flex',
                      position: 'relative',
                      width: 350,
                      height: 350,
                  }}
              >
                  <div
                      style={{
                          display: 'flex',
                          width: '100%',
                          height: '100%',
                          overflow: 'hidden',
                          borderRadius: '5%',
                      }}
                  >
                      <img
                          src={imageUrl}
                          alt="headshot of author"
                          width={350}
                          height={350}
                          style={{
                              objectFit: 'cover',
                          }}
                      />
                  </div>
              </div>

              <div style={{
                display: 'flex',
                marginLeft: '20px',
                flexDirection: 'column',
                backgroundColor: '#c3b1e1',
                width: '100%',
                height: 350,
                borderTopLeftRadius: 10,
                borderBottomLeftRadius: 10,
                }}
              >
                <div style={{display: 'flex', flexDirection: 'column', padding: '0 20px', color: 'white'}}>
                  <h1 style={{ fontSize: '48px', fontFamily: 'ArimoBold', color: '#702963', margin: '4px' }}>{artistName}</h1>
                  <div style={{display: 'flex', flexDirection: 'column'}}>
                    <div style={{display: 'flex', flexDirection: 'column'}}>
                        <div style={{display: 'flex'}}>
                            <p style={{fontSize: '28px', fontFamily: 'ArimoBold', margin: '4px'}}>Location</p>
                        </div>
                        <div style={{display: 'flex'}}>
                            <img src={getURL('/location_pin_icon.png')} alt="Location icon" style={{ width: '20px', height: '20px', marginTop: '4px' }} />
                            <p style={{fontSize: '20px', fontFamily: 'ArimoItalic', margin: '4px'}}>{location}</p>
                        </div>
                    </div>
                    <div style={{display: 'flex', flexDirection: 'column'}}>
                        <div style={{display: 'flex'}}>
                            <p style={{fontSize: '28px', fontFamily: 'ArimoBold', margin: '4px'}}>Rating</p>
                        </div>
                        <div style={{display: 'flex'}}>
                            <p style={{fontSize: '20px', fontFamily: 'ArimoItalic', margin: '4px'}}>{ratingString}</p>
                        </div>
                    </div>
                    <div style={{display: 'flex', flexDirection: 'column'}}>
                        <div style={{display: 'flex'}}>
                            <p style={{fontSize: '28px', fontFamily: 'ArimoBold', margin: '4px'}}>Profession</p>
                        </div>
                        <div style={{display: 'flex'}}>
                            <p style={{fontSize: '20px', fontFamily: 'ArimoItalic', margin: '4px'}}>{jobs.join(', ')}</p>
                        </div>
                    </div>
                </div>
                </div>
              </div>
            </div>

            <div style={{
                display: 'flex',
                flexDirection: 'row',
                position: 'absolute',
                top: '38.8%',
                left: '-11%',
                justifyContent: 'center',
                alignItems: 'center',
                backgroundColor: '#c3b1e1',
                borderRadius: 10, 
                color: 'white',
                paddingLeft: 4,
                paddingRight: 4,
                width: '100%',
            }}>
                <h1 style={{fontFamily: 'ArimoBold', fontSize: '60px', marginRight: '50px', color: '#702963'}}>Top Songs</h1>
                <div style={{display: 'flex', flexDirection: 'column'}}>
                    <div style={{display: 'flex', flexDirection: 'row'}}>
                        <div style={{display: 'flex'}}>
                            <p style={{fontSize: '26px', fontFamily: 'Arimo', margin: '4px'}}>{notableSongs[0].title} |</p>
                        </div>
                        <div style={{display: 'flex'}}>
                            <p style={{fontSize: '20px', fontFamily: 'ArimoItalic', margin: '4px'}}>{notableSongs[0].plays} plays</p>
                        </div>
                    </div>
                    <div style={{display: 'flex', flexDirection: 'row'}}>
                        <div style={{display: 'flex'}}>
                            <p style={{fontSize: '26px', fontFamily: 'Arimo', margin: '4px'}}>{notableSongs[1].title} |</p>
                        </div>
                        <div style={{display: 'flex'}}>
                            <p style={{fontSize: '20px', fontFamily: 'ArimoItalic', margin: '4px'}}>{notableSongs[1].plays} plays</p>
                        </div>
                    </div>
                    <div style={{display: 'flex', flexDirection: 'row'}}>
                        <div style={{display: 'flex'}}>
                            <p style={{fontSize: '26px', fontFamily: 'Arimo', margin: '4px'}}>{notableSongs[2].title} |</p>
                        </div>
                        <div style={{display: 'flex'}}>
                            <p style={{fontSize: '20px', fontFamily: 'ArimoItalic', margin: '4px'}}>{notableSongs[2].plays} plays</p>
                        </div>
                    </div>
                </div>
            </div>

            <div style={{
                display: 'flex',
                flexDirection: 'row',
                position: 'absolute',
                top: '53%',
                right: '0%',
                width: '106%',
                backgroundColor: '#c3b1e1',
                color: 'white',
                borderTopLeftRadius: 10,
                borderBottomLeftRadius: 10,
                paddingLeft: 10,
                paddingRight: 10,
                }}
            >
                <div style={{
                    display: 'flex',
                    flexDirection: 'column',
                }}
                >
                    {(tiktokHandle !== undefined && tiktokHandle !== null && tiktokHandle !== '')
                        ? <div style={{
                            display: 'flex',
                            alignItems: 'center',
                            paddingLeft: 5,
                            paddingRight: 5,
                            marginLeft: 20,
                            borderRadius: 10,
                            height: '85px',
                        }}>
                            <img
                                src={getURL("/tiktok_icon_white.png")}
                                alt="TikTok icon"
                                width={50}
                                height={50}
                                style={{ objectFit: 'cover', }}
                            />
                            <p style={{ marginLeft: '20px', fontSize: '20px', fontFamily: 'ArimoBold' }}>
                                @{tiktokHandle}
                            </p>
                        </div>
                    : null}

                    {(twitterHandle !== undefined && twitterHandle !== null && twitterHandle !== '')
                        ? <div style={{
                            display: 'flex',
                            alignItems: 'center',
                            paddingLeft: 5,
                            paddingRight: 5,
                            marginLeft: 20,
                            borderRadius: 10,
                            height: '85px',
                        }}>
                            <img
                                src={getURL("/twitter_icon_white.png")}
                                alt="Twitter icon"
                                width={50}
                                height={50}
                                style={{ objectFit: 'cover' }}
                            />
                            <p style={{ marginLeft: '20px', fontSize: '20px', fontFamily: 'ArimoBold' }}>
                                @{twitterHandle}
                            </p>
                        </div>
                    : null}
                </div>
                <div style={{
                    display: 'flex',
                    flexDirection: 'column',
                }}
                >
                {/* {(spotifyId !== undefined && spotifyId !== null && spotifyId !== '')
                    ? < div style={{
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        padding: 5,
                        borderRadius: 10,
                        height: '85px',
                    }}>
                        <img
                            src={getURL('/spotify_icon_white.png')}
                            alt="spotify icon"
                            width={80}
                            height={80}
                            style={{ objectFit: 'cover' }}
                        />
                        <p style={{
                            marginLeft: '20px',
                            fontSize: '20px',
                            fontFamily: 'ArimoBold',
                        }}>
                            open.spotify.com/artist/{spotifyId}
                        </p>
                    </div>
                    : null} */}
                {(instagramHandle !== undefined && instagramHandle !== null && instagramHandle !== '')
                    ? <div style={{
                        display: 'flex',
                        alignItems: 'center',
                        paddingLeft: 5,
                        paddingRight: 5,
                        marginLeft: 20,
                        borderRadius: 10,
                        height: '85px',
                    }}>
                        <img
                            src={getURL("/instagram_icon_white.png")}
                            alt="Instagram icon"
                            width={50}
                            height={50}
                            style={{ objectFit: 'cover', }}
                        />
                        <p style={{ marginLeft: '20px', fontSize: '20px', fontFamily: 'ArimoBold' }}>
                            @{instagramHandle}
                        </p>
                    </div>
                : null}
                </div>
                <div style={{display: 'flex', justifyContent: 'center', alignItems: 'center'}}>
                    <h1 style={{ fontSize: '48px', fontFamily: 'ArimoBold', color: '#702963', paddingLeft: '20px', paddingRight: '20px' }}>Socials</h1>
                </div>
            </div>

            <div 
              style={{
                display: 'flex',
                flexDirection: 'column',
                position: 'absolute',
                top: '39%',
                left: '-13%',
                alignItems: 'center',
                width: '100%',
                paddingLeft: '50px',
                paddingRight: '50px',
              }}
            >
                <div
                    style={{
                        display: 'flex',
                        width: '100%',
                        marginTop: '360px',
                        marginBottom: '15px',
                        marginLeft: '120px',
                        backgroundColor: '#c3b1e1',
                        borderTopRightRadius: 10,
                        borderBottomRightRadius: 10,
                        color: 'white',
                        justifyContent: 'center',
                        alignItems: 'center',
                        paddingLeft: '30px',
                        paddingRight: '30px',
                    }}
                >
                    <h1 style={{ fontSize: '48px', fontFamily: 'ArimoBold', color: '#702963', paddingRight: '40px' }}>Bio</h1>
                    <p style={{ textAlign: 'left', fontSize: 16}}>
                        {bio}
                    </p>
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