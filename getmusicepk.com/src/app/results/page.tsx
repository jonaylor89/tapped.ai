'use client';

import { useEffect, useState } from 'react';
import { useAuth } from '@/context/AuthProvider';
import { getURL } from '@/utils/url';
import Image from 'next/image';
import { EPKTheme } from '@/types/themes';
import Link from 'next/link';

// @ts-ignore
import PDFDocument from 'pdfkit/js/pdfkit.standalone'

import SVGtoPDF from 'svg-to-pdfkit'
import blobStream from 'blob-stream'
import { generateEpkSvg } from '@/utils/image_generation';
import { useRouter, useSearchParams } from 'next/navigation';
import { EpkForm } from '@/types/epk_form';
import { getEpkFormById } from '@/utils/database';
import { EpkPayload } from '@/types/epk_payload';

const themes: EPKTheme[] = [
    'funky',
    'tapped',
    'minimalist',
];

const width = 900;
const height = 1200;

const shimmer = (w: number, h: number) => `
<svg width="${w}" height="${h}" version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
  <defs>
    <linearGradient id="g">
      <stop stop-color="#333" offset="20%" />
      <stop stop-color="#222" offset="50%" />
      <stop stop-color="#333" offset="70%" />
    </linearGradient>
  </defs>
  <rect width="${w}" height="${h}" fill="#333" />
  <rect id="r" width="${w}" height="${h}" fill="url(#g)" />
  <animate xlink:href="#r" attributeName="x" from="-${w}" to="${w}" dur="1s" repeatCount="indefinite"  />
</svg>`

const toBase64 = (str: string) =>
  typeof window === 'undefined'
    ? Buffer.from(str).toString('base64')
    : window.btoa(str)

export default function Results() {
    const { user, claim } = useAuth();
    const router = useRouter();
    const searchParams = useSearchParams();
    const formId = searchParams.get('id') ?? null;
    const [error, setError] = useState<boolean>(false);
    const [selectedTheme, setSelectedTheme] = useState<number | null>(null);
    const [form, setForm] = useState<EpkForm | null>(null);

    useEffect(() => {
        const fetchForm = async () => {
            if (user === null) {
                console.debug('user is null')
                return;
            }

            if (formId === null) {
                console.debug('formId is null')
                return;
            }

            const epkForm = await getEpkFormById({
                userId: user.id,
                formId: formId,
            });
            setForm(epkForm);
        };
        fetchForm();
    }, [user, formId]);

    if (formId === null) {
        console.log('formId is null')
        return (
            <>
                <div className='min-h-screen flex justify-center items-center'>
                    <p>There was an error generating your EPK. Please try again later.</p>
                </div>
            </>
        );
    }



    if (error) {
        return (
            <>
                <div className='min-h-screen flex justify-center items-center'>
                    <p>There was an error generating your EPK. Please try again later.</p>
                </div>
            </>
        );
    }

    if (user === null || form === null) {
        return (
            <>
                <div className='min-h-screen flex justify-center items-center'>
                    <p>fetching user...</p>
                </div>
            </>
        );
    }

    console.debug({ user, claim });
    const payload: EpkPayload = {
        ...form,
        twitterHandle: user?.twitterHandle ?? form?.twitterHandle ?? null,
        tiktokHandle: user?.tiktokHandle ?? form?.tiktokHandle ?? null,
        instagramHandle: user?.instagramHandle ?? form?.instagramHandle ?? null,
        tappedRating: (
            user?.overallRating !== undefined &&
            user?.overallRating !== null) ? `${user?.overallRating}` : null,
    }
    const formString = JSON.stringify(payload);
    // const urlParams = Object.entries(user).map(([key, val]) => {
    //     const value = encodeURIComponent(val);
    //     return `${key}=${value}`;
    // }).join('&');
    const imageUrls = themes.map((theme) => {
        const urlParams = new URLSearchParams({
            epkData: formString,
            theme,
        }).toString();
        generateEpkSvg({
            ...payload,
            theme: theme,
            height,
            width,
        }).then((result) => {
            console.log({ result });
        });
        return {
            theme,
            url: getURL(`/epk?${urlParams}`),
        };
    });

    const pdfHandler = async (themeIndex: number) => {
        if (form === null) {
            return;
        }

        const theme = themes[themeIndex];
        const result = await generateEpkSvg({
            ...payload,
            theme: theme,
            height,
            width,
        });

        const doc = new PDFDocument({
            compress: false,
            size: [width, height],
        })
        SVGtoPDF(doc, result, 0, 0, {
            width,
            height,
            preserveAspectRatio: `xMidYMid meet`,
        })
        const stream = doc.pipe(blobStream())
        stream.on('finish', () => {
            const blob = stream.toBlob('application/pdf')
            const objectUrl = URL.createObjectURL(blob)
            console.log({ objectUrl })
            router.push(objectUrl);
        })
        doc.end()
    }

    return (
        <>
            <div
                className="min-h-screen flex flex-col justify-center px-6"
            >
                <div className='flex flex-col'>
                    <div className="h-12" />
                    <div className='md:text-center'>
                        <h1 className='text-4xl font-extrabold'>pick your style</h1>
                    </div>
                    <div className='flex flex-row hide-scroll-bar overflow-x-scroll'>
                        <div className='flex flex-nowrap'>

                            {imageUrls.map(({ url }, index) => (
                                <div
                                    key={index}
                                    onClick={() => { setSelectedTheme(index) }}
                                    className={`w-[256px] md:w-[400px] mr-6 my-6 inline-block rounded-xl ${(selectedTheme === index) && 'border-4 border-white'
                                        }`}
                                >
                                    <Image
                                        src={url}
                                        alt="EPK"
                                        width={512}
                                        height={512}
                                        placeholder={`data:image/svg+xml;base64,${toBase64(shimmer(512, 512))}`}
                                        priority
                                        onError={(e) => { setError(true) }}
                                        className='rounded-lg overflow-hidden'
                                    />
                                </div>
                            ),
                            )}
                        </div>
                    </div>
                    {selectedTheme !== null && (
                        <>
                            <div className='flex flex-col md:flex-row md:justify-center gap-4'>

                                <button
                                    onClick={() => pdfHandler(selectedTheme)}
                                    className='text-2xl font-bold px-12 py-2 rounded-xl bg-blue-600 text-white hover:scale-105 transform transition-all duration-200 ease-in-out'
                                >
                                    get as pdf
                                </button>
                                <Link
                                    href={imageUrls[selectedTheme].url}
                                    download="epk.png"
                                    target="_blank"
                                    rel="noreferrer"
                                    className='text-center text-2xl font-bold px-12 py-2 rounded-xl bg-white/10 text-white/75 hover:scale-105 transform transition-all duration-200 ease-in-out'
                                >
                                    get as png
                                </Link>
                            </div>
                        </>
                    )}
                </div>
            </div>
        </>
    );
}
