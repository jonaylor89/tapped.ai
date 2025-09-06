'use client';

import { redirect, useRouter, useSearchParams } from 'next/navigation';
import { useEffect, useState } from 'react';
import { getAccessCode, marketingPlanListener, useAccessCode } from '@/utils/database';
import { MarketingPlan } from '@/types/marketing_plan';
import Loading from '@/components/loading';
import Processing from '@/components/processing';
import Markdown from 'react-markdown';
import Link from 'next/link';
import { track } from '@vercel/analytics';

const paymentLink = process.env.NEXT_PUBLIC_STRIPE_PAYMENT_LINK;

const Preview = () => {
  const router = useRouter();
  const params = useSearchParams();
  const clientReferenceId = params.get('client_reference_id');
  if (!clientReferenceId) {
    redirect('/');
  }

  const paymentUrl = `${paymentLink}?client_reference_id=${clientReferenceId}`;

  const [marketingPlan, setMarketingPlan] = useState<MarketingPlan | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    console.log({ clientReferenceId });
    marketingPlanListener(clientReferenceId, async (marketingPlan) => {
      setMarketingPlan(marketingPlan);
    });
  }, []);

  const onSubmitHandler = async (e) => {
    e.preventDefault();
    setLoading(true);
    const formData = new FormData(e.currentTarget);
    const uppercaseCode = formData.get('accessCode');
    const theCode = uppercaseCode.toString().toLowerCase();
    console.log({ code: theCode });

    // check if access code exists
    const accessCode = await getAccessCode(theCode);
    if (accessCode === null) {
      setLoading(false);
      alert(`This access code ${theCode} does not exist.`);
      return;
    }

    // check if access code has been used before
    const isValid = !accessCode.used || accessCode.permacode;
    if (!isValid) {
      setLoading(false);
      alert(`This access code ${theCode} has already been used.`);
      return;
    }

    track('submit', {
      method: 'access-code',
    });

    await useAccessCode({
      code: theCode,
      clientReferenceId,
    });

    // if not, redirect them to results with client_reference_id and access_code
    router.push(`/results?client_reference_id=${clientReferenceId}&access_code=${theCode}`);
    setLoading(false);
  };

  if (marketingPlan === null || marketingPlan.status === 'initial') {
    return (
      <Loading />
    );
  }

  if (marketingPlan.status === 'processing') {
    return (
      <Processing />
    );
  }

  const headerRegEx = /^#[^#\n]+([\W\w]*?)/gm;
  const subheaderRegEx = /^##[^#\n]+([\W\w]*?)/gm;
  const headers = marketingPlan?.content?.match(headerRegEx) ?? [];
  const subheaders = marketingPlan?.content?.match(subheaderRegEx) ?? [];
  console.log(headers);
  console.log(subheaders);

  if (loading) {
    return (
      <Loading />
    );
  }

  return (
    <div className="flex flex-col lg:flex-row px-4 py-4 lg:px-24 lg:pt-24">
      <div className='flex flex-col items-center'>
        <h1 className='text-6xl font-extrabold py-6 px-6 text-center'>Preview</h1>
        <p className='md:w-1/2 lg:w-full text-center font-thin pb-12'>
        Take one step closer to being independent and not relying on record labels.
        </p>
        <div>
          <h1 className='text-center text-3xl'>$9.99</h1>
          <div className='h-6'></div>
          <Link
            href={paymentUrl}
            className='bg-blue-600 hover:bg-blue-800 text-white font-extrabold py-4 px-6 rounded'
          >
            Buy Full Plan
          </Link>
        </div>
        <div className='h-8'></div>
        <div className="grid w-full grid-cols-3 items-center my-4">
          <div className="h-px bg-gray-300"></div>
          <span className="text-center text-white">or</span>
          <div className="h-px bg-gray-300"></div>
        </div>
        <div className='h-8'></div>
        <div className='w-72'>
          <div className="relative h-10 w-full min-w-[200px]">
            <form onSubmit={onSubmitHandler}>
              <div className="relative flex h-10 w-full min-w-[200px] max-w-[24rem]">
                <input
                  name="accessCode"
                  className="lowercase peer h-full w-full rounded-[7px] border border-blue-gray-200 bg-transparent px-3 py-2.5 pr-20 font-sans text-sm font-normal text-blue-gray-700 outline outline-0 transition-all placeholder-shown:border placeholder-shown:border-blue-gray-200 placeholder-shown:border-t-blue-gray-200 focus:border-2 focus:border-pink-500 focus:border-t-transparent focus:outline-0 disabled:border-0 disabled:bg-blue-gray-50"
                  placeholder=" "
                  required
                />
                <button
                  className="!absolute right-1 top-1 z-10 select-none rounded bg-blue-600 py-2 px-4 text-center align-middle font-sans text-xs font-bold uppercase text-white shadow-md shadow-pink-500/20 transition-all hover:shadow-lg hover:shadow-pink-500/40 focus:opacity-[0.85] focus:shadow-none active:opacity-[0.85] active:shadow-none peer-placeholder-shown:pointer-events-none peer-placeholder-shown:bg-blue-gray-500 peer-placeholder-shown:opacity-50 peer-placeholder-shown:shadow-none"
                  type="submit"
                  data-ripple-light="true"
                >
                  Submit
                </button>
                <label className="before:content[' '] after:content[' '] pointer-events-none absolute left-0 -top-1.5 flex h-full w-full select-none text-[11px] font-normal leading-tight text-blue-gray-400 transition-all before:pointer-events-none before:mt-[6.5px] before:mr-1 before:box-border before:block before:h-1.5 before:w-2.5 before:rounded-tl-md before:border-t before:border-l before:border-blue-gray-200 before:transition-all after:pointer-events-none after:mt-[6.5px] after:ml-1 after:box-border after:block after:h-1.5 after:w-2.5 after:flex-grow after:rounded-tr-md after:border-t after:border-r after:border-blue-gray-200 after:transition-all peer-placeholder-shown:text-sm peer-placeholder-shown:leading-[3.75] peer-placeholder-shown:text-blue-gray-500 peer-placeholder-shown:before:border-transparent peer-placeholder-shown:after:border-transparent peer-focus:text-[11px] peer-focus:leading-tight peer-focus:text-pink-500 peer-focus:before:border-t-2 peer-focus:before:border-l-2 peer-focus:before:!border-pink-500 peer-focus:after:border-t-2 peer-focus:after:border-r-2 peer-focus:after:!border-pink-500 peer-disabled:text-transparent peer-disabled:before:border-transparent peer-disabled:after:border-transparent peer-disabled:peer-placeholder-shown:text-blue-gray-500">
                  Access Code
                </label>
              </div>
            </form>
          </div>
        </div>
      </div>
      <div className='h-8 w-4 lg:h-12 lg:w-12'></div>
      <div className='bg-white p-8 rounded-md'>
        <Markdown className="text-black prose lg:prose-xl" children={headers[0]} />
        {subheaders.map((subheader) => (
          <div className='py-6'>
            <Markdown className="text-black prose lg:prose-xl" children={subheader} />
            <div className='blur-lg text-black py-4'>
            Blanditiis occaecati deleniti nisi hic placeat officiis nemo eius. Architecto sapiente omnis ut impedit. Sequi ex nam temporibus voluptate excepturi. Quasi illum pariatur illum eum.

            Exercitationem neque pariatur eum eos qui excepturi. Deserunt eligendi perferendis ut. Accusantium libero nobis incidunt. Itaque molestiae laboriosam dolorum eos consequatur nesciunt.

            Ducimuslksjdbgn excepturi est voluptas consequatur reprehenderit ipsa non quis. Sunt magnam eos aut deserunt eum pariatur est impedit. Quidem quae aut praesentium voluptatem architecto eligendi quisquam. Consectetur quaerat architecto ea non dignissimos. Eum ea molestias ut.

            Minus possimus expedita est at qui et. Necessitatibus ut omnis modi aut velit quo. Rerum esse magni praesentium est. Eos non nostrum laudantium fugit vel commodi possimus. Vitae minima ab vitae sunt. Distinctio quae delectus nemo.
            </div>
          </div>
        ),)}
      </div>
    </div>
  );
};

export default Preview;
